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

typedef struct {
    const char *model_path;     // path to the .gguf file
    int32_t     n_ctx;          // context window size (default 4096)
    int32_t     n_gpu_layers;   // Metal layers (-1 = all)
    int32_t     n_threads;      // CPU threads (0 = auto)
    float       temperature;    // 0.0 = greedy
    float       top_p;          // nucleus sampling (0.95 default)
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

// Creates the engine and loads the model. Blocks until loaded.
// Returns ES_STATUS_OK on success; *out_engine is valid only on success.
ESStatus es_create(const ESConfig *config, ESEngineRef *out_engine);

// Frees the engine and all associated resources.
void es_destroy(ESEngineRef engine);

// ── Generation ────────────────────────────────────────────────────────────────

// Starts a NEW conversation (resets KV cache) and generates a response.
// system_prompt: optional role description (NULL = no system prompt).
// user_text:     user message.
// max_tokens:    max tokens to generate.
// on_token:      called for each generated text piece (from the calling thread).
// on_done:       called when generation ends (status = OK or CANCELLED).
// user_data:     passed through to both callbacks.
// BLOCKS until done or cancelled. Call from a background thread.
ESStatus es_generate(ESEngineRef  engine,
                     const char  *system_prompt,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data);

// Continues the current conversation without resetting the KV cache.
// Appends the user turn and generates the next assistant response.
ESStatus es_continue(ESEngineRef  engine,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data);

// ── Control ───────────────────────────────────────────────────────────────────

// Thread-safe: signals the current generation to stop at the next token boundary.
void es_cancel(ESEngineRef engine);

// Resets conversation context (clears KV cache and history).
void es_reset(ESEngineRef engine);

// ── Status ────────────────────────────────────────────────────────────────────

int32_t es_ctx_used(ESEngineRef engine);
int32_t es_ctx_max(ESEngineRef engine);

// ── Hardware ─────────────────────────────────────────────────────────────────

ESHardwareInfo es_get_hw_info(void);

#ifdef __cplusplus
}
#endif

#endif // ES_API_H
