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

// Pipeline stages, reported via es_orch_stage_cb as each one begins.
// Values match ESAgentStage in es_api.h (0/1/2).
typedef enum {
    ES_ORCH_STAGE_PLANNING  = 0,
    ES_ORCH_STAGE_EXECUTING = 1,
    ES_ORCH_STAGE_REVIEWING = 2,
} es_orch_stage_t;

// Called when each pipeline stage begins (nullable).
typedef void (*es_orch_stage_cb)(es_orch_stage_t stage, void *user_data);

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

// Run the pipeline (Planner → Executor [→ Critic]).
// out_buf must hold at least out_len bytes.
// system_prompt (nullable): extra instructions injected into every agent.
// run_critic: when true, runs the Critic synthesis stage and streams it as the
//   final answer; when false, the Executor's output is the final streamed answer.
// stream_cb (nullable): called with each token piece (all stages stream live).
// stage_cb  (nullable): called as each stage begins.
// Returns chars written to out_buf, or -1 on error.
int32_t es_orchestrator_run(es_orchestrator_t *orch,
                             const char *system_prompt, const char *user_query,
                             int32_t max_tokens_per_stage, bool run_critic,
                             char *out_buf, int32_t out_len,
                             es_orch_stream_cb stream_cb, void *stream_ud,
                             es_orch_stage_cb  stage_cb,  void *stage_ud);

#endif // ES_ORCHESTRATOR_H
