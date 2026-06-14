#ifndef ES_AGENT_H
#define ES_AGENT_H

#include "es_engine.h"
#include "es_kvcache.h"
#include <stdint.h>
#include <stdbool.h>

// --- Embershard Agent ---
// An agent is the same model running with a different context.
// Each agent has an isolated seq_id in the KV cache, a system prompt that defines
// its role, and its own sampler. The control plane creates and destroys agents;
// the model itself is stateless.

#define ES_AGENT_MAX_SYS_PROMPT 4096
#define ES_AGENT_PROMPT_BUF     65536  // buffer per chat template formattato

typedef enum {
    ES_ROLE_PLANNER  = 0,
    ES_ROLE_EXECUTOR = 1,
    ES_ROLE_CRITIC   = 2,
    ES_ROLE_CUSTOM   = 3,
} es_agent_role_t;

typedef struct {
    es_agent_role_t       role;
    llama_seq_id          seq_id;
    int32_t               pos;         // current position in this agent's KV sequence
    char                  name[32];
    char                  system_prompt[ES_AGENT_MAX_SYS_PROMPT];
    struct llama_sampler *sampler;
    es_engine_t          *engine;
    es_kvcache_t         *kvcache;
    // Token history buffer (used if the sequence is ever persisted to disk)
    llama_token          *token_history;
    int32_t               n_token_hist;
    int32_t               token_hist_cap;
} es_agent_t;

// Lifecycle
es_agent_t *es_agent_create(es_engine_t *engine, es_kvcache_t *kvcache,
                             es_agent_role_t role, const char *name,
                             const char *system_prompt, float temperature);
void        es_agent_free(es_agent_t *agent);

// Reset: clears this agent's KV sequence and position.
void es_agent_reset(es_agent_t *agent);

// Run: format prompt via chat template, ingest, generate into out_buf.
// out_buf must be at least max_len bytes. Resets agent state before running.
// Returns number of chars written to out_buf, or -1 on error.
int32_t es_agent_run(es_agent_t *agent, const char *input,
                     char *out_buf, int32_t max_len, int32_t max_tokens);

// Streaming variant: calls token_cb(piece, user_data) for each generated piece.
// Returns tokens generated, or -1 on error.
int32_t es_agent_run_stream(es_agent_t *agent, const char *input,
                             int32_t max_tokens,
                             void (*token_cb)(const char *piece, void *user_data),
                             void *user_data);

const char *es_agent_role_name(es_agent_role_t role);

#endif // ES_AGENT_H
