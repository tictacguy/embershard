#ifndef ES_API_H
#define ES_API_H

// --- Embershard Public API ---
// Opaque interface for Swift/Objective-C. No llama.cpp types are exposed.
// All functions use standard C types and opaque pointers.
// Thread-safety: es_generate / es_continue block — call from a background thread.
// es_cancel is the only function safe to call from any thread.

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque engine handle
typedef struct es_engine_s *ESEngineRef;

typedef enum {
    ES_STATUS_OK         = 0,
    ES_STATUS_ERR_MODEL  = 1,
    ES_STATUS_ERR_CTX    = 2,
    ES_STATUS_ERR_GEN    = 3,
    ES_STATUS_CANCELLED  = 4,
    ES_STATUS_OOM        = 5,
} ESStatus;

// KV cache quantization level
typedef enum {
    ES_KV_QUANT_F16  = 0,   // full precision (default)
    ES_KV_QUANT_Q8_0 = 1,   // ~50% memory reduction
    ES_KV_QUANT_Q4_0 = 2,   // ~75% memory reduction
} ESKVQuantType;

// Agent pipeline stages
typedef enum {
    ES_STAGE_PLANNING  = 0,
    ES_STAGE_EXECUTING = 1,
    ES_STAGE_REVIEWING = 2,
} ESAgentStage;

typedef struct {
    const char *model_path;     // path to the .gguf file
    int32_t     n_ctx;          // context window size (default 4096)
    int32_t     n_gpu_layers;   // Metal layers (-1 = all)
    int32_t     n_threads;      // CPU threads (0 = auto)
    float       temperature;    // 0.0 = greedy
    float       top_p;          // nucleus sampling (0.95 default)
    ESKVQuantType kv_quant;     // KV cache quantization (default F16)
    // Called during model loading with progress in [0.0, 1.0]. Return false to abort.
    bool (*on_progress)(float progress, void *user_data);
    void *progress_ud;
} ESConfig;

typedef struct {
    uint64_t total_ram;      // bytes
    uint64_t available_ram;  // bytes
    char     chip[128];      // e.g., "Apple M2 Pro"
    int32_t  cpu_cores;
} ESHardwareInfo;

// ── Lifecycle ─────────────────────────────────────────────────────────────────

ESStatus es_create(const ESConfig *config, ESEngineRef *out_engine);
void     es_destroy(ESEngineRef engine);

// ── Generation ────────────────────────────────────────────────────────────────

ESStatus es_generate(ESEngineRef  engine,
                     const char  *system_prompt,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data);

ESStatus es_continue(ESEngineRef  engine,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data);

// ── Agentic pipeline ─────────────────────────────────────────────────────────
// Runs Planner → Executor → Critic. on_stage fires at each stage transition.
// on_token fires for each output piece from the Critic (final) stage.
ESStatus es_orchestrate(ESEngineRef engine,
                         const char *user_query,
                         int32_t     max_tokens_per_stage,
                         void (*on_stage)(ESAgentStage stage, void *ud),
                         void (*on_token)(const char *piece, void *ud),
                         void (*on_done)(ESStatus status, void *ud),
                         void       *user_data);

// ── Control ───────────────────────────────────────────────────────────────────

void es_cancel(ESEngineRef engine);
void es_reset(ESEngineRef engine);

// ── Status ────────────────────────────────────────────────────────────────────

int32_t es_ctx_used(ESEngineRef engine);
int32_t es_ctx_max(ESEngineRef engine);
int32_t es_last_n_tokens(ESEngineRef engine);  // tokens generated in last call

// ── Hardware ─────────────────────────────────────────────────────────────────

ESHardwareInfo es_get_hw_info(void);

#ifdef __cplusplus
}
#endif

#endif // ES_API_H
