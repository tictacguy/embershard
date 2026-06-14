#include "es_engine.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>

// Helper: populate batch slot manually (no llama_batch_add in current API)
static void batch_add(struct llama_batch *batch, llama_token token, llama_pos pos,
                      llama_seq_id seq_id, bool logits) {
    int32_t i = batch->n_tokens;
    batch->token[i] = token;
    batch->pos[i] = pos;
    batch->n_seq_id[i] = 1;
    batch->seq_id[i][0] = seq_id;
    batch->logits[i] = logits ? 1 : 0;
    batch->n_tokens++;
}

static void batch_clear(struct llama_batch *batch) {
    batch->n_tokens = 0;
}

// Shim to bridge llama_progress_callback → es_engine_config_t.on_load_progress
static bool es_load_progress_shim(float progress, void *ud) {
    es_engine_t *eng = (es_engine_t *)ud;
    if (atomic_load(&eng->cancel)) return false; // abort if cancelled
    if (eng->config.on_load_progress) {
        return eng->config.on_load_progress(progress, eng->config.load_progress_ud);
    }
    return true;
}

es_engine_t *es_engine_init(es_engine_config_t config) {
    es_engine_t *engine = calloc(1, sizeof(es_engine_t));
    if (!engine) return NULL;

    engine->config = config;
    atomic_init(&engine->cancel, false);

    // Model params
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = config.n_gpu_layers;
    model_params.use_mmap = config.use_mmap;
    model_params.progress_callback = es_load_progress_shim;
    model_params.progress_callback_user_data = engine;

    engine->model = llama_model_load_from_file(config.model_path, model_params);
    if (!engine->model) {
        fprintf(stderr, "[embershard] failed to load model: %s\n", config.model_path);
        free(engine);
        return NULL;
    }

    // Context params
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = config.n_ctx;
    ctx_params.n_batch = config.n_batch;
    ctx_params.n_threads = config.n_threads;
    ctx_params.flash_attn_type = config.flash_attn
        ? LLAMA_FLASH_ATTN_TYPE_ENABLED
        : LLAMA_FLASH_ATTN_TYPE_DISABLED;

    engine->ctx = llama_init_from_model(engine->model, ctx_params);
    if (!engine->ctx) {
        fprintf(stderr, "[embershard] failed to create context\n");
        llama_model_free(engine->model);
        free(engine);
        return NULL;
    }

    engine->n_vocab = llama_vocab_n_tokens(llama_model_get_vocab(engine->model));
    engine->n_ctx_max = config.n_ctx;
    engine->pos = 0;
    engine->ready = true;

    return engine;
}

void es_engine_free(es_engine_t *engine) {
    if (!engine) return;
    if (engine->ctx) llama_free(engine->ctx);
    if (engine->model) llama_model_free(engine->model);
    free(engine);
}

bool es_engine_ingest(es_engine_t *engine, const char *text) {
    if (!engine || !engine->ready || !text) return false;

    const struct llama_vocab *vocab = llama_model_get_vocab(engine->model);
    int32_t text_len = (int32_t)strlen(text);

    // Tokenize
    int32_t n_tokens = text_len + 16;
    llama_token *tokens = malloc(sizeof(llama_token) * n_tokens);
    n_tokens = llama_tokenize(vocab, text, text_len, tokens, n_tokens, true, true);
    if (n_tokens < 0) {
        n_tokens = -n_tokens;
        tokens = realloc(tokens, sizeof(llama_token) * n_tokens);
        n_tokens = llama_tokenize(vocab, text, text_len, tokens, n_tokens, true, true);
    }
    if (n_tokens < 0) {
        free(tokens);
        return false;
    }

    // Process in batches
    struct llama_batch batch = llama_batch_init(engine->config.n_batch, 0, 1);

    for (int32_t i = 0; i < n_tokens; i++) {
        batch_add(&batch, tokens[i], engine->pos, 0,
                  (i == n_tokens - 1));  // logits only on last token
        engine->pos++;

        if (batch.n_tokens >= engine->config.n_batch || i == n_tokens - 1) {
            if (llama_decode(engine->ctx, batch) != 0) {
                llama_batch_free(batch);
                free(tokens);
                return false;
            }
            batch_clear(&batch);
        }
    }

    llama_batch_free(batch);
    free(tokens);
    return true;
}

const char *es_engine_token_to_str(es_engine_t *engine, int32_t token) {
    if (!engine) return NULL;
    const struct llama_vocab *vocab = llama_model_get_vocab(engine->model);
    // Thread-local buffer: safe for concurrent calls from different threads.
    static _Thread_local char buf[512];
    int32_t n = llama_token_to_piece(vocab, token, buf, sizeof(buf) - 1, 0, true);
    if (n < 0) return NULL;
    buf[n] = '\0';
    return buf;
}

bool es_engine_is_eos(es_engine_t *engine, int32_t token) {
    if (!engine) return true;
    return llama_vocab_is_eog(llama_model_get_vocab(engine->model), token);
}

int32_t es_engine_get_pos(es_engine_t *engine) {
    return engine ? engine->pos : 0;
}

bool es_engine_reset(es_engine_t *engine) {
    if (!engine) return false;
    llama_memory_clear(llama_get_memory(engine->ctx), true);
    engine->pos = 0;
    return true;
}

int32_t es_engine_ctx_used(es_engine_t *engine) {
    return engine ? engine->pos : 0;
}

int32_t es_engine_ctx_max(es_engine_t *engine) {
    return engine ? engine->n_ctx_max : 0;
}

void es_engine_cancel(es_engine_t *engine) {
    if (engine) atomic_store(&engine->cancel, true);
}

void es_engine_uncancel(es_engine_t *engine) {
    if (engine) atomic_store(&engine->cancel, false);
}

// ---- Sampler factory ----

struct llama_sampler *es_engine_make_sampler(float temperature, float top_p) {
    struct llama_sampler *s = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(s, llama_sampler_init_greedy());
    } else {
        if (top_p < 1.0f) {
            llama_sampler_chain_add(s, llama_sampler_init_top_p(top_p, 1));
        }
        llama_sampler_chain_add(s, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(s, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }
    return s;
}

void es_engine_free_sampler(struct llama_sampler *sampler) {
    if (sampler) llama_sampler_free(sampler);
}

// ---- Multi-sequence inference ----

int32_t es_engine_ingest_seq(es_engine_t *engine, const char *text,
                              llama_seq_id seq_id, int32_t start_pos,
                              bool add_special) {
    if (!engine || !engine->ready || !text) return -1;

    const struct llama_vocab *vocab = llama_model_get_vocab(engine->model);
    int32_t text_len = (int32_t)strlen(text);

    int32_t n_tokens = text_len + 16;
    llama_token *tokens = malloc(sizeof(llama_token) * n_tokens);
    if (!tokens) return -1;

    n_tokens = llama_tokenize(vocab, text, text_len, tokens, n_tokens, add_special, true);
    if (n_tokens < 0) {
        n_tokens = -n_tokens;
        tokens = realloc(tokens, sizeof(llama_token) * n_tokens);
        n_tokens = llama_tokenize(vocab, text, text_len, tokens, n_tokens, add_special, true);
    }
    if (n_tokens < 0) { free(tokens); return -1; }

    struct llama_batch batch = llama_batch_init(engine->config.n_batch, 0, 1);
    int32_t pos = start_pos;
    int32_t total = n_tokens;

    for (int32_t i = 0; i < total; i++) {
        batch_add(&batch, tokens[i], pos, seq_id, (i == total - 1));
        pos++;

        if (batch.n_tokens >= engine->config.n_batch || i == total - 1) {
            if (llama_decode(engine->ctx, batch) != 0) {
                llama_batch_free(batch);
                free(tokens);
                return -1;
            }
            batch_clear(&batch);
        }
    }

    llama_batch_free(batch);
    free(tokens);
    return total;
}

llama_token es_engine_step_seq(es_engine_t *engine, struct llama_sampler *sampler,
                                llama_seq_id seq_id, int32_t *pos) {
    if (!engine || !engine->ready || !sampler || !pos) return -1;
    if (atomic_load(&engine->cancel)) return -1;

    llama_token token = llama_sampler_sample(sampler, engine->ctx, -1);

    struct llama_batch batch = llama_batch_init(1, 0, 1);
    batch_add(&batch, token, *pos, seq_id, true);
    (*pos)++;

    if (llama_decode(engine->ctx, batch) != 0) {
        llama_batch_free(batch);
        return -1;
    }

    llama_batch_free(batch);
    return token;
}

// ---- KV sequence wrappers ----

void es_engine_kv_seq_rm(es_engine_t *engine, llama_seq_id seq_id, int32_t p0, int32_t p1) {
    if (!engine) return;
    llama_memory_seq_rm(llama_get_memory(engine->ctx), seq_id, p0, p1);
}

void es_engine_kv_seq_cp(es_engine_t *engine, llama_seq_id src, llama_seq_id dst,
                          int32_t p0, int32_t p1) {
    if (!engine) return;
    llama_memory_seq_cp(llama_get_memory(engine->ctx), src, dst, p0, p1);
}

void es_engine_kv_seq_add(es_engine_t *engine, llama_seq_id seq_id,
                           int32_t p0, int32_t p1, int32_t delta) {
    if (!engine) return;
    llama_memory_seq_add(llama_get_memory(engine->ctx), seq_id, p0, p1, delta);
}

void es_engine_kv_seq_keep(es_engine_t *engine, llama_seq_id seq_id) {
    if (!engine) return;
    llama_memory_seq_keep(llama_get_memory(engine->ctx), seq_id);
}

llama_pos es_engine_kv_seq_pos_max(es_engine_t *engine, llama_seq_id seq_id) {
    if (!engine) return -1;
    return llama_memory_seq_pos_max(llama_get_memory(engine->ctx), seq_id);
}

bool es_engine_kv_can_shift(es_engine_t *engine) {
    if (!engine) return false;
    return llama_memory_can_shift(llama_get_memory(engine->ctx));
}

// ---- Chat template ----

int32_t es_engine_apply_chat_template(es_engine_t *engine,
                                       const struct llama_chat_message *messages,
                                       int32_t n_messages, bool add_ass,
                                       char *buf, int32_t buf_size) {
    if (!engine || !messages || !buf) return -1;
    const char *tmpl = llama_model_chat_template(engine->model, NULL);
    int32_t n = llama_chat_apply_template(tmpl, messages, (size_t)n_messages,
                                          add_ass, buf, buf_size);
    if (n > buf_size) {
        // Buffer too small — return required size as negative (caller must resize)
        return -n;
    }
    return n;
}
