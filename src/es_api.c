#include "es_api.h"
#include "es_engine.h"
#include "es_kvcache.h"
#include "es_memory.h"
#include "llama.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>

// macOS hardware info
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <unistd.h>

// ── Internal conversation state ───────────────────────────────────────────────

#define ES_API_MAX_TURNS     64
#define ES_API_PROMPT_CAP    131072  // 128 KB for formatted chat template
#define ES_API_BATCH_SIZE    512
#define ES_API_MAX_SYS       4096

typedef struct {
    char  role[16];
    char *content;
} es_api_turn_t;

// Extended engine object (opaque to callers)
typedef struct es_engine_s {
    es_engine_t      *inner;        // raw inference engine
    es_kvcache_t     *kvcache;
    struct llama_sampler *sampler;
    // Conversation history for chat template application
    es_api_turn_t     turns[ES_API_MAX_TURNS * 2];
    int               n_turns;
    char              system_prompt[ES_API_MAX_SYS];
    // Formatted text length after last assistant turn (for incremental ingest)
    int32_t           last_fmt_len;
    bool              first_turn;   // true before any generation
} ESEngine;

// ── Progress shim ─────────────────────────────────────────────────────────────

typedef struct {
    bool (*user_cb)(float, void *);
    void *user_ud;
} ProgressShimCtx;

static bool progress_shim(float p, void *ud) {
    ProgressShimCtx *ctx = (ProgressShimCtx *)ud;
    if (ctx->user_cb) return ctx->user_cb(p, ctx->user_ud);
    return true;
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

ESStatus es_create(const ESConfig *config, ESEngineRef *out_engine) {
    if (!config || !out_engine) return ES_STATUS_ERR_MODEL;

    ESEngine *eng = calloc(1, sizeof(ESEngine));
    if (!eng) return ES_STATUS_OOM;

    ProgressShimCtx shim_ctx = {
        .user_cb = config->on_progress,
        .user_ud = config->progress_ud,
    };

    int32_t n_threads = config->n_threads > 0
                        ? config->n_threads
                        : (int32_t)sysconf(_SC_NPROCESSORS_ONLN);

    es_engine_config_t inner_cfg = {
        .model_path        = config->model_path,
        .n_gpu_layers      = config->n_gpu_layers != 0 ? config->n_gpu_layers : -1,
        .n_ctx             = config->n_ctx > 0 ? config->n_ctx : 4096,
        .n_batch           = ES_API_BATCH_SIZE,
        .n_threads         = n_threads,
        .use_mmap          = true,
        .flash_attn        = true,
        .on_load_progress  = progress_shim,
        .load_progress_ud  = &shim_ctx,
    };

    eng->inner = es_engine_init(inner_cfg);
    if (!eng->inner) { free(eng); return ES_STATUS_ERR_MODEL; }

    eng->kvcache = es_kvcache_create(eng->inner);
    if (!eng->kvcache) {
        es_engine_free(eng->inner);
        free(eng);
        return ES_STATUS_OOM;
    }

    float temp  = config->temperature >= 0.0f ? config->temperature : 0.7f;
    float top_p = config->top_p > 0.0f ? config->top_p : 0.95f;
    eng->sampler = es_engine_make_sampler(temp, top_p);

    eng->n_turns    = 0;
    eng->last_fmt_len = 0;
    eng->first_turn = true;

    *out_engine = eng;
    return ES_STATUS_OK;
}

void es_destroy(ESEngineRef engine) {
    if (!engine) return;
    ESEngine *eng = (ESEngine *)engine;
    for (int i = 0; i < eng->n_turns; i++) free(eng->turns[i].content);
    es_engine_free_sampler(eng->sampler);
    es_kvcache_free(eng->kvcache);
    es_engine_free(eng->inner);
    free(eng);
}

// ── Internal: conversation management ────────────────────────────────────────

static void conv_add(ESEngine *eng, const char *role, const char *content) {
    if (eng->n_turns >= ES_API_MAX_TURNS * 2) return;
    snprintf(eng->turns[eng->n_turns].role, 16, "%s", role);
    eng->turns[eng->n_turns].content = strdup(content);
    eng->n_turns++;
}

static void conv_clear(ESEngine *eng) {
    for (int i = 0; i < eng->n_turns; i++) free(eng->turns[i].content);
    eng->n_turns = 0;
}

// Build formatted prompt via chat template.
// Returns byte length written to buf, or -1 on error.
static int32_t build_formatted(ESEngine *eng, bool add_ass, char *buf, int32_t cap) {
    int n_msgs = eng->n_turns;
    if (n_msgs == 0) return 0;

    struct llama_chat_message *msgs = malloc(sizeof(*msgs) * (size_t)n_msgs);
    if (!msgs) return -1;
    for (int i = 0; i < n_msgs; i++) {
        msgs[i].role    = eng->turns[i].role;
        msgs[i].content = eng->turns[i].content;
    }
    int32_t len = es_engine_apply_chat_template(eng->inner, msgs, n_msgs, add_ass, buf, cap);
    free(msgs);
    return len;
}

// ── Internal: generate loop ───────────────────────────────────────────────────

typedef struct {
    void (*on_token)(const char *, void *);
    void (*on_done)(ESStatus, void *);
    void *user_data;
    char  accum[131072];
    int   accum_len;
} GenCtx;

static ESStatus run_generation(ESEngine *eng, int32_t max_tokens, GenCtx *ctx) {
    const struct llama_vocab *vocab = llama_model_get_vocab(eng->inner->model);
    char tok_buf[512];
    es_engine_uncancel(eng->inner);

    for (int32_t i = 0; i < max_tokens; i++) {
        llama_token tok = es_engine_step_seq(eng->inner, eng->sampler,
                                              0, &eng->inner->pos);
        if (tok < 0) {
            // -1 = error or cancelled
            ESStatus st = atomic_load(&eng->inner->cancel)
                          ? ES_STATUS_CANCELLED : ES_STATUS_ERR_GEN;
            if (ctx->on_done) ctx->on_done(st, ctx->user_data);
            return st;
        }
        if (es_engine_is_eos(eng->inner, tok)) break;

        int32_t n = llama_token_to_piece(vocab, tok, tok_buf, sizeof(tok_buf) - 1, 0, true);
        if (n <= 0) break;
        tok_buf[n] = '\0';

        if (ctx->on_token) ctx->on_token(tok_buf, ctx->user_data);

        // Accumulate response for conversation history
        if (ctx->accum_len + n < (int32_t)sizeof(ctx->accum) - 1) {
            memcpy(ctx->accum + ctx->accum_len, tok_buf, (size_t)n);
            ctx->accum_len += n;
        }
    }
    ctx->accum[ctx->accum_len] = '\0';

    if (ctx->on_done) ctx->on_done(ES_STATUS_OK, ctx->user_data);
    return ES_STATUS_OK;
}

// ── Generation ────────────────────────────────────────────────────────────────

ESStatus es_generate(ESEngineRef  engine,
                     const char  *system_prompt,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data) {
    if (!engine || !user_text) return ES_STATUS_ERR_GEN;
    ESEngine *eng = (ESEngine *)engine;

    // Full reset for a new conversation
    es_engine_reset(eng->inner);
    conv_clear(eng);
    eng->last_fmt_len = 0;
    eng->first_turn   = true;

    if (system_prompt && system_prompt[0]) {
        snprintf(eng->system_prompt, sizeof(eng->system_prompt), "%s", system_prompt);
        conv_add(eng, "system", eng->system_prompt);
    }
    conv_add(eng, "user", user_text);

    char *fmt = malloc((size_t)ES_API_PROMPT_CAP);
    if (!fmt) return ES_STATUS_OOM;

    int32_t fmt_len = build_formatted(eng, true, fmt, ES_API_PROMPT_CAP);
    if (fmt_len <= 0) { free(fmt); return ES_STATUS_ERR_GEN; }

    int32_t n = es_engine_ingest_seq(eng->inner, fmt, 0, eng->inner->pos, true);
    free(fmt);
    if (n < 0) return ES_STATUS_ERR_GEN;
    eng->inner->pos += n;
    eng->first_turn = false;

    GenCtx ctx = { .on_token=on_token, .on_done=on_done, .user_data=user_data };
    ESStatus st = run_generation(eng, max_tokens > 0 ? max_tokens : 512, &ctx);

    if (st == ES_STATUS_OK && ctx.accum_len > 0) {
        conv_add(eng, "assistant", ctx.accum);
        // Update last_fmt_len for next es_continue
        char *buf = malloc((size_t)ES_API_PROMPT_CAP);
        if (buf) {
            int32_t full = build_formatted(eng, false, buf, ES_API_PROMPT_CAP);
            if (full > 0) eng->last_fmt_len = full;
            free(buf);
        }
    }
    return st;
}

ESStatus es_continue(ESEngineRef  engine,
                     const char  *user_text,
                     int32_t      max_tokens,
                     void (*on_token)(const char *piece, void *ud),
                     void (*on_done)(ESStatus status, void *ud),
                     void        *user_data) {
    if (!engine || !user_text) return ES_STATUS_ERR_GEN;
    ESEngine *eng = (ESEngine *)engine;

    conv_add(eng, "user", user_text);

    char *fmt = malloc((size_t)ES_API_PROMPT_CAP);
    if (!fmt) return ES_STATUS_OOM;

    int32_t fmt_len = build_formatted(eng, true, fmt, ES_API_PROMPT_CAP);
    if (fmt_len <= 0) { free(fmt); return ES_STATUS_ERR_GEN; }

    // Ingest only the new suffix since last turn
    const char *new_part = fmt + eng->last_fmt_len;
    int32_t n = es_engine_ingest_seq(eng->inner, new_part, 0, eng->inner->pos, false);
    free(fmt);
    if (n < 0) return ES_STATUS_ERR_GEN;
    eng->inner->pos += n;

    GenCtx ctx = { .on_token=on_token, .on_done=on_done, .user_data=user_data };
    ESStatus st = run_generation(eng, max_tokens > 0 ? max_tokens : 512, &ctx);

    if (st == ES_STATUS_OK && ctx.accum_len > 0) {
        conv_add(eng, "assistant", ctx.accum);
        char *buf = malloc((size_t)ES_API_PROMPT_CAP);
        if (buf) {
            int32_t full = build_formatted(eng, false, buf, ES_API_PROMPT_CAP);
            if (full > 0) eng->last_fmt_len = full;
            free(buf);
        }
    }
    return st;
}

// ── Control ───────────────────────────────────────────────────────────────────

void es_cancel(ESEngineRef engine) {
    if (!engine) return;
    ESEngine *eng = (ESEngine *)engine;
    es_engine_cancel(eng->inner);
}

void es_reset(ESEngineRef engine) {
    if (!engine) return;
    ESEngine *eng = (ESEngine *)engine;
    es_engine_reset(eng->inner);
    conv_clear(eng);
    eng->last_fmt_len = 0;
    eng->first_turn   = true;
}

int32_t es_ctx_used(ESEngineRef engine) {
    if (!engine) return 0;
    return es_engine_ctx_used(((ESEngine *)engine)->inner);
}

int32_t es_ctx_max(ESEngineRef engine) {
    if (!engine) return 0;
    return es_engine_ctx_max(((ESEngine *)engine)->inner);
}

// ── Hardware ─────────────────────────────────────────────────────────────────

ESHardwareInfo es_get_hw_info(void) {
    ESHardwareInfo info = {0};

    // Total RAM
    uint64_t ram = 0;
    size_t len = sizeof(ram);
    sysctlbyname("hw.memsize", &ram, &len, NULL, 0);
    info.total_ram = ram;

    // Available RAM via vm_statistics
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size;
    host_page_size(mach_host_self(), &page_size);
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                           (host_info64_t)&vm_stats, &count) == KERN_SUCCESS) {
        info.available_ram = (uint64_t)(vm_stats.free_count +
                                         vm_stats.inactive_count) * page_size;
    }

    // CPU brand string (returns "Apple M2" etc. on Apple Silicon)
    char brand[256] = {0};
    size_t brand_len = sizeof(brand);
    sysctlbyname("machdep.cpu.brand_string", brand, &brand_len, NULL, 0);
    if (brand[0] == '\0') {
        // Fallback: use hw.model
        sysctlbyname("hw.model", brand, &brand_len, NULL, 0);
    }
    snprintf(info.chip, sizeof(info.chip), "%s", brand);

    // Physical CPU cores
    int32_t ncpu = 0;
    len = sizeof(ncpu);
    sysctlbyname("hw.physicalcpu", &ncpu, &len, NULL, 0);
    info.cpu_cores = ncpu > 0 ? ncpu : (int32_t)sysconf(_SC_NPROCESSORS_ONLN);

    return info;
}
