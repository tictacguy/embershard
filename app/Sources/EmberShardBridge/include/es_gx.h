#ifndef ES_GX_H
#define ES_GX_H

// --- Embershard GX: native ggml inference engine ---
//
// A from-scratch transformer decoder built directly on the ggml tensor library
// and the Metal backend. It does NOT use libllama for inference: it reads the
// GGUF itself, uploads weights to the GPU, owns a resident KV cache, builds its
// own compute graph, and runs it. ggml provides only the tensor ops/kernels.
//
// Multi-architecture: the graph builder dispatches on the GGUF architecture.
// Validated families: llama, qwen2. Implemented: gemma / gemma2.
//
// Performance model: weights and the KV cache stay resident in GPU memory; the
// allocator for graph intermediates is persistent and grows monotonically; the
// KV cache is F16. Generation is O(n) per token (incremental), not O(n^2).

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct es_gx_model es_gx_model;

typedef enum {
    ES_GX_ARCH_LLAMA  = 0,
    ES_GX_ARCH_QWEN2  = 1,
    ES_GX_ARCH_GEMMA  = 2,
    ES_GX_ARCH_GEMMA2 = 3,
    ES_GX_ARCH_UNKNOWN = 99,
} es_gx_arch;

// Load a GGUF (single-file or the first shard of a `-00001-of-N` split), detect
// architecture + hyper-parameters, upload weights to Metal, and allocate a
// resident KV cache of `n_ctx` tokens (0 = sensible cap). kv_quant: 0=F16,
// 1=Q8_0, 2=Q4_0 (quantized cache uses the manual attention path).
// Returns NULL on failure (unsupported arch, I/O error).
es_gx_model *es_gx_load(const char *gguf_path, int n_ctx, int kv_quant);
void         es_gx_free(es_gx_model *m);

// Reset conversation state (logically clears the KV cache; n_past -> 0).
void es_gx_reset(es_gx_model *m);

// Evaluate `n_tokens` tokens that logically start at absolute position `n_past`,
// appending their K/V into the resident cache. Returns the logits for the LAST
// token (n_vocab floats owned by the model, valid until the next eval), or NULL.
// For generation: prefill once with the prompt (n_past=0), then call repeatedly
// with a single token and the running n_past.
const float *es_gx_eval(es_gx_model *m, const int32_t *tokens, int n_tokens, int n_past);

// Convenience: reset + eval(tokens, n_tokens, 0). Stateless single shot.
const float *es_gx_forward(es_gx_model *m, const int32_t *tokens, int n_tokens);

// ── Sampling configuration ───────────────────────────────────────────────────
typedef struct {
    float    temp;            // <= 0 => greedy
    float    top_p;           // nucleus mass (1.0 = off)
    int      top_k;           // keep top-k logits (0 = off)
    float    min_p;           // min relative probability (0 = off)
    float    repeat_penalty;  // 1.0 = off
    int      repeat_last_n;   // how many recent tokens to penalize
    uint32_t seed;            // RNG seed (0 = fixed default)
} es_gx_sampling;

// Set the sampler used by es_gx_generate_stream (and chat/generate).
void es_gx_set_sampling(es_gx_model *m, es_gx_sampling s);

// ── High-level streaming generation ──────────────────────────────────────────
typedef void (*es_gx_token_cb)(const char *piece, void *user_data);

// Generate from a raw prompt string. temp<=0 => greedy; else temperature+top_p.
// Streams decoded UTF-8 pieces to cb. Returns #tokens generated (or -1).
int es_gx_generate(es_gx_model *m, const char *prompt, int max_tokens,
                   float temp, float top_p, bool add_bos, bool parse_special,
                   es_gx_token_cb cb, void *user_data);

// Chat helper: applies the per-architecture chat template (llama3 / qwen2) to
// `system` (nullable) + `user`, then generates. Resets state each call.
int es_gx_chat(es_gx_model *m, const char *system, const char *user, int max_tokens,
               float temp, float top_p, es_gx_token_cb cb, void *user_data);

// ── Stateful multi-turn primitives (KV cache reused across calls) ─────────────
// Encode `text` and append it to the KV cache at the current position (prefill
// the new turn only). Returns 0 on success, -1 on error.
int es_gx_ingest(es_gx_model *m, const char *text, bool add_bos, bool parse_special);

// Sample/stream from the CURRENT logits (set by the last ingest/eval), appending
// each generated token to the KV cache. Uses the sampler set via
// es_gx_set_sampling. Stops on end-of-generation or max_tokens. Returns #tokens.
int es_gx_generate_stream(es_gx_model *m, int max_tokens, es_gx_token_cb cb, void *user_data);

int es_gx_n_past(const es_gx_model *m);

// Request cancellation of an in-flight generate_stream (thread-safe, any thread).
void es_gx_cancel(es_gx_model *m);

// Probe a GGUF's architecture WITHOUT loading weights (cheap, metadata only).
// Returns the arch enum; ES_GX_ARCH_UNKNOWN if unsupported/unreadable.
es_gx_arch es_gx_probe_arch(const char *gguf_path);

// Tokenizer (native, GGUF byte-level BPE) — es_gx owns it.
int  es_gx_encode(es_gx_model *m, const char *text, int32_t *out, int max_out,
                  bool add_bos, bool parse_special);
int  es_gx_decode(es_gx_model *m, int32_t id, char *buf, int buf_size);
int  es_gx_bos(const es_gx_model *m);
int  es_gx_eos(const es_gx_model *m);
bool es_gx_token_is_eog(const es_gx_model *m, int32_t id);  // end-of-generation
bool es_gx_is_spm(const es_gx_model *m);                    // SentencePiece tokenizer

// Introspection
int         es_gx_n_vocab(const es_gx_model *m);
int         es_gx_n_embd(const es_gx_model *m);
int         es_gx_n_ctx(const es_gx_model *m);
int         es_gx_n_ctx_train(const es_gx_model *m);
es_gx_arch  es_gx_get_arch(const es_gx_model *m);
const char *es_gx_arch_name(const es_gx_model *m);

#ifdef __cplusplus
}
#endif

#endif // ES_GX_H
