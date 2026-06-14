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
    "You are an execution agent. You will receive a plan and the original "
    "user query. Execute the plan and produce a thorough answer. "
    "Follow the numbered steps and show your work.";

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

// Streaming callback state for critic stage
typedef struct {
    char    *buf;
    int32_t  len;
    int32_t  cap;
    es_orch_stream_cb user_cb;
    void    *user_data;
} critic_stream_state_t;

static void critic_token_cb(const char *piece, void *ud) {
    critic_stream_state_t *s = (critic_stream_state_t *)ud;
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

int32_t es_orchestrator_run(es_orchestrator_t *orch, const char *user_query,
                             int32_t max_tokens_per_stage,
                             char *out_buf, int32_t out_len,
                             es_orch_stream_cb stream_cb, void *stream_ud) {
    if (!orch || !user_query || !out_buf || out_len <= 0) return -1;

    char *plan    = malloc((size_t)ES_ORCH_BUF_SIZE);
    char *draft   = malloc((size_t)ES_ORCH_BUF_SIZE);
    if (!plan || !draft) {
        free(plan); free(draft);
        return -1;
    }

    // ── Stage 1: Planner ──────────────────────────────────────────────────
    if (orch->verbose) fprintf(stderr, "[orch] stage=planner ...\n");

    int32_t plan_len = es_agent_run(orch->planner, user_query,
                                    plan, ES_ORCH_BUF_SIZE, max_tokens_per_stage);
    if (plan_len < 0) {
        fprintf(stderr, "[orch] planner failed\n");
        free(plan); free(draft);
        return -1;
    }
    if (orch->verbose) fprintf(stderr, "[orch] plan (%d chars):\n%s\n", plan_len, plan);

    // ── Stage 2: Executor ─────────────────────────────────────────────────
    // Build executor input: plan + original query
    char *exec_input = malloc((size_t)(ES_ORCH_BUF_SIZE + strlen(user_query) + 128));
    if (!exec_input) { free(plan); free(draft); return -1; }
    snprintf(exec_input, ES_ORCH_BUF_SIZE + strlen(user_query) + 128,
             "Original query: %s\n\nPlan:\n%s\n\nNow execute the plan step by step.",
             user_query, plan);

    if (orch->verbose) fprintf(stderr, "[orch] stage=executor ...\n");

    int32_t draft_len = es_agent_run(orch->executor, exec_input,
                                     draft, ES_ORCH_BUF_SIZE, max_tokens_per_stage);
    free(exec_input);
    if (draft_len < 0) {
        fprintf(stderr, "[orch] executor failed\n");
        free(plan); free(draft);
        return -1;
    }
    if (orch->verbose) fprintf(stderr, "[orch] draft (%d chars):\n%s\n", draft_len, draft);

    // ── Stage 3: Critic ───────────────────────────────────────────────────
    char *critic_input = malloc((size_t)(ES_ORCH_BUF_SIZE * 2 + strlen(user_query) + 256));
    if (!critic_input) { free(plan); free(draft); return -1; }
    snprintf(critic_input, ES_ORCH_BUF_SIZE * 2 + strlen(user_query) + 256,
             "Original query: %s\n\nPlan:\n%s\n\nDraft answer:\n%s\n\n"
             "Provide the final, corrected, well-structured answer.",
             user_query, plan, draft);

    if (orch->verbose) fprintf(stderr, "[orch] stage=critic ...\n");

    critic_stream_state_t css = {
        .buf       = malloc((size_t)ES_ORCH_FINAL_SIZE),
        .len       = 0,
        .cap       = ES_ORCH_FINAL_SIZE,
        .user_cb   = stream_cb,
        .user_data = stream_ud,
    };
    if (!css.buf) { free(critic_input); free(plan); free(draft); return -1; }
    css.buf[0] = '\0';

    int32_t n_gen = es_agent_run_stream(orch->critic, critic_input,
                                        max_tokens_per_stage, critic_token_cb, &css);
    free(critic_input);
    free(plan);
    free(draft);

    if (n_gen < 0) {
        free(css.buf);
        return -1;
    }

    // Copy critic output to caller's buffer
    int32_t copy_len = css.len < out_len - 1 ? css.len : out_len - 1;
    memcpy(out_buf, css.buf, (size_t)copy_len);
    out_buf[copy_len] = '\0';
    free(css.buf);

    if (orch->verbose) fprintf(stderr, "[orch] done (%d tokens generated by critic)\n", n_gen);
    return copy_len;
}
