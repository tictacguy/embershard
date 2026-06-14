#ifndef ES_ORCHESTRATOR_H
#define ES_ORCHESTRATOR_H

#include "es_engine.h"
#include "es_kvcache.h"
#include "es_agent.h"
#include <stdint.h>
#include <stdbool.h>

// --- Embershard Orchestrator ---
// Central coordinator: decomposes the problem, drives agents, aggregates results.
// Pipeline: Planner → Executor → Critic
//
// Planner: breaks the query into numbered steps.
// Executor: executes each step (or treats the plan as a single task).
// Critic: synthesizes the results into a final coherent response.
//
// All three share the same physical model with separate KV sequences.

#define ES_ORCH_MAX_AGENTS  8
#define ES_ORCH_BUF_SIZE    16384  // per ogni output di agente
#define ES_ORCH_FINAL_SIZE  32768  // output finale aggregato

// Called with each token piece during critic (final stage) generation.
typedef void (*es_orch_stream_cb)(const char *piece, void *user_data);

typedef struct {
    es_engine_t  *engine;
    es_kvcache_t *kvcache;
    es_agent_t   *planner;
    es_agent_t   *executor;
    es_agent_t   *critic;
    bool          verbose; // print intermediate agent outputs to stderr

} es_orchestrator_t;

// Lifecycle
es_orchestrator_t *es_orchestrator_create(es_engine_t *engine, bool verbose);
void               es_orchestrator_free(es_orchestrator_t *orch);

// Run full pipeline (Planner → Executor → Critic).
// out_buf must hold at least out_len bytes.
// stream_cb (nullable): called with each token piece from the critic stage.
// Returns chars written to out_buf, or -1 on error.
int32_t es_orchestrator_run(es_orchestrator_t *orch, const char *user_query,
                             int32_t max_tokens_per_stage,
                             char *out_buf, int32_t out_len,
                             es_orch_stream_cb stream_cb, void *stream_ud);

#endif // ES_ORCHESTRATOR_H
