#ifndef ES_ENGINE_H
#define ES_ENGINE_H

#include "llama.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

// --- Embershard Engine ---
// Not a wrapper. A control plane that treats llama.cpp as a stateless executor
// and owns the full inference lifecycle.

typedef enum {
    ES_OK              = 0,
    ES_ERR_NULL        = 1,
    ES_ERR_MODEL_LOAD  = 2,
    ES_ERR_CTX_INIT    = 3,
    ES_ERR_TOKENIZE    = 4,
    ES_ERR_DECODE      = 5,
    ES_ERR_OOM         = 6,
    ES_ERR_CANCELLED   = 7,
} es_error_t;

typedef struct {
    int32_t n_gpu_layers;    // layers offloaded to Metal (-1 = all)
    int32_t n_ctx;           // maximum context size
    int32_t n_batch;         // batch size for prompt processing
    int32_t n_threads;       // CPU threads (used for CPU fallback and prompt processing)
    bool    use_mmap;        // memory-mapped model loading
    bool    flash_attn;      // enable flash attention if available
    const char *model_path;  // path to the GGUF file
    // Called during model loading with progress in [0.0, 1.0]. Return false to abort.
    bool (*on_load_progress)(float progress, void *user_data);
    void *load_progress_ud;
} es_engine_config_t;

typedef struct {
    struct llama_model   *model;
    struct llama_context *ctx;
    es_engine_config_t    config;
    int32_t               n_vocab;
    int32_t               n_ctx_max;
    int32_t               pos;
    bool                  ready;
    // Atomic cancel flag — set from any thread, checked in the generation loop.
    atomic_bool           cancel;
} es_engine_t;

// Lifecycle
es_engine_t *es_engine_init(es_engine_config_t config);
void         es_engine_free(es_engine_t *engine);

// Simple ingestion for single-shot prompts (uses seq 0, adds BOS/EOS).
bool es_engine_ingest(es_engine_t *engine, const char *text);

const char *es_engine_token_to_str(es_engine_t *engine, int32_t token);
bool        es_engine_is_eos(es_engine_t *engine, int32_t token);

// Context control
int32_t es_engine_get_pos(es_engine_t *engine);
bool    es_engine_reset(es_engine_t *engine);

// Info
int32_t es_engine_ctx_used(es_engine_t *engine);
int32_t es_engine_ctx_max(es_engine_t *engine);

// Cancellation — safe to call from any thread
void es_engine_cancel(es_engine_t *engine);
void es_engine_uncancel(es_engine_t *engine);

// --- Sampler factory ---
// temperature <= 0 selects greedy decoding; top_p is ignored in that case.
struct llama_sampler *es_engine_make_sampler(float temperature, float top_p);
void                  es_engine_free_sampler(struct llama_sampler *sampler);

// --- Multi-sequence inference ---
// Tokenize text and ingest it into seq_id starting at start_pos.
// add_special: add BOS/EOS tokens (true on the first turn, false for continuations).
// Returns tokens ingested, or -1 on error.
int32_t es_engine_ingest_seq(es_engine_t *engine, const char *text,
                              llama_seq_id seq_id, int32_t start_pos,
                              bool add_special);

// Sample and decode one token for seq_id at *pos, then increment *pos.
// Returns the token id, or -1 on error / cancellation.
llama_token es_engine_step_seq(es_engine_t *engine, struct llama_sampler *sampler,
                                llama_seq_id seq_id, int32_t *pos);

// --- KV sequence control ---
void      es_engine_kv_seq_rm  (es_engine_t *engine, llama_seq_id seq_id, int32_t p0, int32_t p1);
void      es_engine_kv_seq_cp  (es_engine_t *engine, llama_seq_id src, llama_seq_id dst, int32_t p0, int32_t p1);
void      es_engine_kv_seq_add (es_engine_t *engine, llama_seq_id seq_id, int32_t p0, int32_t p1, int32_t delta);
void      es_engine_kv_seq_keep(es_engine_t *engine, llama_seq_id seq_id);
llama_pos es_engine_kv_seq_pos_max(es_engine_t *engine, llama_seq_id seq_id);
bool      es_engine_kv_can_shift(es_engine_t *engine);

// --- Chat template ---
// Returns the formatted length, or -n (negative required size) if buf is too small.
// add_ass=true prepends the assistant role prefix.
int32_t es_engine_apply_chat_template(es_engine_t *engine,
                                       const struct llama_chat_message *messages,
                                       int32_t n_messages, bool add_ass,
                                       char *buf, int32_t buf_size);

#endif // ES_ENGINE_H
