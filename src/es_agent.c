#include "es_agent.h"
#include "llama.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static const char *role_names[] = { "planner", "executor", "critic", "custom" };

const char *es_agent_role_name(es_agent_role_t role) {
    if (role < 0 || role > ES_ROLE_CUSTOM) return "unknown";
    return role_names[role];
}

es_agent_t *es_agent_create(es_engine_t *engine, es_kvcache_t *kvcache,
                             es_agent_role_t role, const char *name,
                             const char *system_prompt, float temperature) {
    if (!engine || !kvcache) return NULL;

    llama_seq_id seq_id = es_kvcache_alloc_seq(kvcache);
    if (seq_id < 0) {
        fprintf(stderr, "[es_agent] failed to allocate seq_id for agent '%s'\n", name);
        return NULL;
    }

    es_agent_t *agent = calloc(1, sizeof(es_agent_t));
    if (!agent) { es_kvcache_free_seq(kvcache, seq_id); return NULL; }

    agent->role    = role;
    agent->seq_id  = seq_id;
    agent->pos     = 0;
    agent->engine  = engine;
    agent->kvcache = kvcache;
    snprintf(agent->name, sizeof(agent->name), "%s", name ? name : role_names[role]);
    snprintf(agent->system_prompt, sizeof(agent->system_prompt), "%s",
             system_prompt ? system_prompt : "");

    agent->sampler = es_engine_make_sampler(temperature, 0.95f);

    agent->token_hist_cap = 4096;
    agent->token_history  = malloc(sizeof(llama_token) * (size_t)agent->token_hist_cap);
    agent->n_token_hist   = 0;

    return agent;
}

void es_agent_free(es_agent_t *agent) {
    if (!agent) return;
    es_kvcache_free_seq(agent->kvcache, agent->seq_id);
    es_engine_free_sampler(agent->sampler);
    free(agent->token_history);
    free(agent);
}

void es_agent_reset(es_agent_t *agent) {
    if (!agent) return;
    es_engine_kv_seq_rm(agent->engine, agent->seq_id, 0, -1);
    agent->pos          = 0;
    agent->n_token_hist = 0;
}

// Append token to the agent's history, growing if needed.
static void agent_track_token(es_agent_t *agent, llama_token tok) {
    if (agent->n_token_hist >= agent->token_hist_cap) {
        agent->token_hist_cap *= 2;
        agent->token_history = realloc(agent->token_history,
                                       sizeof(llama_token) * (size_t)agent->token_hist_cap);
    }
    agent->token_history[agent->n_token_hist++] = tok;
}

// Build the formatted prompt for this agent using the model's chat template.
// Falls back to a simple "System: ...\nUser: ...\nAssistant:" if template fails.
static int32_t build_prompt(es_agent_t *agent, const char *input,
                             char *buf, int32_t buf_size) {
    struct llama_chat_message msgs[2];
    msgs[0].role    = "system";
    msgs[0].content = agent->system_prompt[0] ? agent->system_prompt : "You are a helpful assistant.";
    msgs[1].role    = "user";
    msgs[1].content = input;

    int32_t n = es_engine_apply_chat_template(agent->engine, msgs, 2, true, buf, buf_size);
    if (n > 0 && n <= buf_size) return n;

    // Fallback: simple concatenation (works for most instruction-tuned models)
    n = snprintf(buf, (size_t)buf_size,
                 "<|system|>\n%s\n<|user|>\n%s\n<|assistant|>\n",
                 msgs[0].content, msgs[1].content);
    return (n > 0 && n < buf_size) ? n : -1;
}

int32_t es_agent_run(es_agent_t *agent, const char *input,
                     char *out_buf, int32_t max_len, int32_t max_tokens) {
    if (!agent || !input || !out_buf || max_len <= 0 || max_tokens <= 0) return -1;

    es_agent_reset(agent);

    char *prompt_buf = malloc((size_t)ES_AGENT_PROMPT_BUF);
    if (!prompt_buf) return -1;

    int32_t prompt_len = build_prompt(agent, input, prompt_buf, ES_AGENT_PROMPT_BUF);
    if (prompt_len <= 0) { free(prompt_buf); return -1; }

    int32_t n_ingested = es_engine_ingest_seq(agent->engine, prompt_buf,
                                               agent->seq_id, agent->pos, true);
    free(prompt_buf);
    if (n_ingested < 0) return -1;
    agent->pos += n_ingested;

    const struct llama_vocab *vocab = llama_model_get_vocab(agent->engine->model);
    char    tok_buf[256];
    int32_t out_len = 0;

    for (int32_t i = 0; i < max_tokens && out_len < max_len - 1; i++) {
        llama_token tok = es_engine_step_seq(agent->engine, agent->sampler,
                                              agent->seq_id, &agent->pos);
        if (tok < 0 || es_engine_is_eos(agent->engine, tok)) break;

        agent_track_token(agent, tok);

        int32_t n_piece = llama_token_to_piece(vocab, tok, tok_buf, sizeof(tok_buf), 0, true);
        if (n_piece <= 0) break;

        int32_t can = max_len - 1 - out_len;
        if (n_piece > can) n_piece = can;
        memcpy(out_buf + out_len, tok_buf, (size_t)n_piece);
        out_len += n_piece;
    }
    out_buf[out_len] = '\0';
    return out_len;
}

int32_t es_agent_run_stream(es_agent_t *agent, const char *input,
                             int32_t max_tokens,
                             void (*token_cb)(const char *piece, void *user_data),
                             void *user_data) {
    if (!agent || !input || !token_cb || max_tokens <= 0) return -1;

    es_agent_reset(agent);

    char *prompt_buf = malloc((size_t)ES_AGENT_PROMPT_BUF);
    if (!prompt_buf) return -1;

    int32_t prompt_len = build_prompt(agent, input, prompt_buf, ES_AGENT_PROMPT_BUF);
    if (prompt_len <= 0) { free(prompt_buf); return -1; }

    int32_t n_ingested = es_engine_ingest_seq(agent->engine, prompt_buf,
                                               agent->seq_id, agent->pos, true);
    free(prompt_buf);
    if (n_ingested < 0) return -1;
    agent->pos += n_ingested;

    const struct llama_vocab *vocab = llama_model_get_vocab(agent->engine->model);
    char    tok_buf[256];
    int32_t n_gen = 0;

    for (int32_t i = 0; i < max_tokens; i++) {
        llama_token tok = es_engine_step_seq(agent->engine, agent->sampler,
                                              agent->seq_id, &agent->pos);
        if (tok < 0 || es_engine_is_eos(agent->engine, tok)) break;

        agent_track_token(agent, tok);
        n_gen++;

        int32_t n_piece = llama_token_to_piece(vocab, tok, tok_buf, sizeof(tok_buf) - 1, 0, true);
        if (n_piece <= 0) break;
        tok_buf[n_piece] = '\0';
        token_cb(tok_buf, user_data);
    }

    return n_gen;
}
