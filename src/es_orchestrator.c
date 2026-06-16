#include "es_orchestrator.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Default system prompts for each role
static const char PLANNER_SYS[] =
    "You are a planning agent. Your task is to analyze the user's request "
    "and break it down into clear, numbered steps (1., 2., 3., ...). "
    "Be concise. List only the steps, no explanations.";

static const char EXECUTOR_SYS[] =
    "You are an execution agent. You receive a plan and the original user query. "
    "Carry out the plan and write the complete, well-structured final answer "
    "addressed directly to the user. Use clear Markdown (headings, lists, code "
    "blocks) where helpful. Do not mention the plan or that you are an agent — "
    "just deliver the answer.";

static const char CRITIC_SYS[] =
    "You are a synthesis agent. You will receive the original query, a plan, "
    "and a draft answer. Your job is to review the draft, correct any errors, "
    "and produce a clear, well-structured final response. "
    "Be direct and accurate.";

es_orchestrator_t *es_orchestrator_create(es_engine_t *engine, bool verbose) {
    if (!engine) return NULL;

    es_orchestrator_t *orch = calloc(1, sizeof(es_orchestrator_t));
    if (!orch) return NULL;

    orch->engine  = engine;
    orch->verbose = verbose;

    orch->kvcache = es_kvcache_create(engine);
    if (!orch->kvcache) { free(orch); return NULL; }

    // Temperature: planner greedy (structured output), executor 0.3 (factual),
    // critic 0.2 (conservative synthesis)
    orch->planner  = es_agent_create(engine, orch->kvcache, ES_ROLE_PLANNER,
                                     "planner",  PLANNER_SYS,  0.0f);
    orch->executor = es_agent_create(engine, orch->kvcache, ES_ROLE_EXECUTOR,
                                     "executor", EXECUTOR_SYS, 0.3f);
    orch->critic   = es_agent_create(engine, orch->kvcache, ES_ROLE_CRITIC,
                                     "critic",   CRITIC_SYS,   0.2f);

    if (!orch->planner || !orch->executor || !orch->critic) {
        es_orchestrator_free(orch);
        return NULL;
    }

    return orch;
}

void es_orchestrator_free(es_orchestrator_t *orch) {
    if (!orch) return;
    if (orch->planner)  es_agent_free(orch->planner);
    if (orch->executor) es_agent_free(orch->executor);
    if (orch->critic)   es_agent_free(orch->critic);
    if (orch->kvcache)  es_kvcache_free(orch->kvcache);
    free(orch);
}

// Streaming accumulator: forwards each piece to the user callback (so every
// stage streams live to the UI) while also buffering the full text so it can be
// fed into the next stage's prompt.
typedef struct {
    char    *buf;
    int32_t  len;
    int32_t  cap;
    es_orch_stream_cb user_cb;
    void    *user_data;
} stream_accum_t;

static void accum_token_cb(const char *piece, void *ud) {
    stream_accum_t *s = (stream_accum_t *)ud;
    int32_t piece_len = (int32_t)strlen(piece);

    // Grow buffer if needed
    while (s->len + piece_len + 1 > s->cap) {
        s->cap *= 2;
        s->buf = realloc(s->buf, (size_t)s->cap);
    }
    memcpy(s->buf + s->len, piece, (size_t)piece_len);
    s->len += piece_len;
    s->buf[s->len] = '\0';

    if (s->user_cb) s->user_cb(piece, s->user_data);
}

// Prepend an optional system prompt (e.g. an active skill) as a context header
// to an agent input. Caller owns the returned buffer.
static char *with_system(const char *system_prompt, const char *body) {
    if (!system_prompt || !system_prompt[0]) return strdup(body);
    size_t n = strlen(system_prompt) + strlen(body) + 64;
    char *out = malloc(n);
    if (!out) return NULL;
    snprintf(out, n, "Follow these instructions:\n%s\n\n%s", system_prompt, body);
    return out;
}

int32_t es_orchestrator_run(es_orchestrator_t *orch,
                             const char *system_prompt, const char *user_query,
                             int32_t max_tokens_per_stage, bool run_critic,
                             char *out_buf, int32_t out_len,
                             es_orch_stream_cb stream_cb, void *stream_ud,
                             es_orch_stage_cb  stage_cb,  void *stage_ud) {
    if (!orch || !user_query || !out_buf || out_len <= 0) return -1;

    // ── Stage 1: Planner ──────────────────────────────────────────────────
    // Every stage streams live to the UI through stream_cb; the accumulator also
    // captures the full text to build the next stage's prompt.
    if (stage_cb) stage_cb(ES_ORCH_STAGE_PLANNING, stage_ud);
    if (orch->verbose) fprintf(stderr, "[orch] stage=planner ...\n");

    char *plan_input = with_system(system_prompt, user_query);
    if (!plan_input) return -1;

    stream_accum_t plan_acc = {
        .buf = malloc((size_t)ES_ORCH_BUF_SIZE), .len = 0, .cap = ES_ORCH_BUF_SIZE,
        .user_cb = stream_cb, .user_data = stream_ud,
    };
    if (!plan_acc.buf) { free(plan_input); return -1; }
    plan_acc.buf[0] = '\0';

    int32_t plan_gen = es_agent_run_stream(orch->planner, plan_input,
                                           max_tokens_per_stage, accum_token_cb, &plan_acc);
    free(plan_input);
    if (plan_gen < 0) {
        fprintf(stderr, "[orch] planner failed\n");
        free(plan_acc.buf);
        return -1;
    }
    char *plan = plan_acc.buf;
    if (orch->verbose) fprintf(stderr, "[orch] plan (%d chars):\n%s\n", plan_acc.len, plan);
    // Free planner KV — its output is already captured in `plan`
    es_engine_kv_seq_rm(orch->engine, orch->planner->seq_id, 0, -1);
    orch->planner->pos = 0;

    // ── Stage 2: Executor ─────────────────────────────────────────────────
    // When there is no critic stage, the executor writes the final user-facing
    // answer directly; otherwise it produces a draft for the critic to refine.
    char *exec_body = malloc((size_t)(plan_acc.len + strlen(user_query) + 192));
    if (!exec_body) { free(plan); return -1; }
    sprintf(exec_body,
            "Original query: %s\n\nPlan:\n%s\n\n%s",
            user_query, plan,
            run_critic ? "Now execute the plan step by step."
                       : "Now write the complete, well-structured final answer for the user.");
    char *exec_input = with_system(system_prompt, exec_body);
    free(exec_body);
    if (!exec_input) { free(plan); return -1; }

    if (stage_cb) stage_cb(ES_ORCH_STAGE_EXECUTING, stage_ud);
    if (orch->verbose) fprintf(stderr, "[orch] stage=executor ...\n");

    stream_accum_t draft_acc = {
        .buf = malloc((size_t)ES_ORCH_FINAL_SIZE), .len = 0, .cap = ES_ORCH_FINAL_SIZE,
        .user_cb = stream_cb, .user_data = stream_ud,
    };
    if (!draft_acc.buf) { free(exec_input); free(plan); return -1; }
    draft_acc.buf[0] = '\0';

    int32_t draft_gen = es_agent_run_stream(orch->executor, exec_input,
                                            max_tokens_per_stage, accum_token_cb, &draft_acc);
    free(exec_input);
    if (draft_gen < 0) {
        fprintf(stderr, "[orch] executor failed\n");
        free(draft_acc.buf); free(plan);
        return -1;
    }
    char *draft = draft_acc.buf;
    if (orch->verbose) fprintf(stderr, "[orch] draft (%d chars):\n%s\n", draft_acc.len, draft);

    // ── No critic: executor output IS the final answer ────────────────────
    if (!run_critic) {
        int32_t copy_len = draft_acc.len < out_len - 1 ? draft_acc.len : out_len - 1;
        memcpy(out_buf, draft, (size_t)copy_len);
        out_buf[copy_len] = '\0';
        free(plan); free(draft);
        if (orch->verbose) fprintf(stderr, "[orch] done (%d tokens by executor)\n", draft_gen);
        return copy_len;
    }

    // Free executor KV — its output is already captured in `draft`
    es_engine_kv_seq_rm(orch->engine, orch->executor->seq_id, 0, -1);
    orch->executor->pos = 0;

    // ── Stage 3: Critic ───────────────────────────────────────────────────
    char *critic_body = malloc((size_t)(plan_acc.len + draft_acc.len + strlen(user_query) + 256));
    if (!critic_body) { free(plan); free(draft); return -1; }
    sprintf(critic_body,
            "Original query: %s\n\nPlan:\n%s\n\nDraft answer:\n%s\n\n"
            "Provide the final, corrected, well-structured answer.",
            user_query, plan, draft);
    char *critic_input = with_system(system_prompt, critic_body);
    free(critic_body);
    if (!critic_input) { free(plan); free(draft); return -1; }

    if (stage_cb) stage_cb(ES_ORCH_STAGE_REVIEWING, stage_ud);
    if (orch->verbose) fprintf(stderr, "[orch] stage=critic ...\n");

    stream_accum_t crit_acc = {
        .buf = malloc((size_t)ES_ORCH_FINAL_SIZE), .len = 0, .cap = ES_ORCH_FINAL_SIZE,
        .user_cb = stream_cb, .user_data = stream_ud,
    };
    if (!crit_acc.buf) { free(critic_input); free(plan); free(draft); return -1; }
    crit_acc.buf[0] = '\0';

    int32_t n_gen = es_agent_run_stream(orch->critic, critic_input,
                                        max_tokens_per_stage, accum_token_cb, &crit_acc);
    free(critic_input);
    free(plan);
    free(draft);

    if (n_gen < 0) {
        free(crit_acc.buf);
        return -1;
    }

    // Copy critic output to caller's buffer
    int32_t copy_len = crit_acc.len < out_len - 1 ? crit_acc.len : out_len - 1;
    memcpy(out_buf, crit_acc.buf, (size_t)copy_len);
    out_buf[copy_len] = '\0';
    free(crit_acc.buf);

    if (orch->verbose) fprintf(stderr, "[orch] done (%d tokens generated by critic)\n", n_gen);
    return copy_len;
}
