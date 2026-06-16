// es_gx.c — native ggml inference engine with a resident KV cache (no libllama).
// See es_gx.h. We read the GGUF, upload weights + a KV cache to Metal, and build
// our own incremental transformer decode graph for llama / qwen2 / gemma(2).

#include "es_gx.h"
#include "es_tok.h"

#include "ggml.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"
#include "ggml-metal.h"
#include "gguf.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <math.h>

#define GX_MAX_LAYERS 256
#define GX_MAX_SHARDS 64
#define GX_PAD(x, n)  (((x) + (n) - 1) & ~((n) - 1))

typedef struct {
    struct ggml_tensor *attn_norm;
    struct ggml_tensor *wq, *wk, *wv, *wo;
    struct ggml_tensor *bq, *bk, *bv, *bo;   // optional (qwen2 qkv bias)
    struct ggml_tensor *ffn_norm;
    struct ggml_tensor *ffn_gate, *ffn_up, *ffn_down;
    struct ggml_tensor *post_attn_norm;       // gemma2
    struct ggml_tensor *post_ffn_norm;        // gemma2
    struct ggml_tensor *k_cache, *v_cache;    // resident, F16 [n_embd_*_gqa, n_ctx]
} gx_layer;

struct es_gx_model {
    ggml_backend_t              backend;
    ggml_backend_buffer_type_t  buft;
    ggml_gallocr_t              galloc;       // persistent compute allocator

    struct gguf_context        *gguf;            // shard 0 (metadata + tokenizer)
    struct ggml_context        *ctx_w_arr[GX_MAX_SHARDS];
    ggml_backend_buffer_t       buf_w_arr[GX_MAX_SHARDS];
    int                         n_shards;
    struct ggml_context        *ctx_kv;
    ggml_backend_buffer_t       buf_kv;
    enum ggml_type              kv_type;         // F16 / Q8_0 / Q4_0

    es_gx_arch arch;
    char       arch_name[32];
    int  n_layer, n_embd, n_head, n_head_kv, n_ff, n_vocab, n_ctx_train, n_ctx;
    int  head_dim, n_rot, n_embd_k_gqa, n_embd_v_gqa;
    float f_norm_eps;
    float rope_freq_base, rope_freq_scale;
    int   rope_type;
    float f_attn_scale, f_embd_scale;
    bool  gated_gelu, has_post_norm;
    bool  use_flash;

    struct ggml_tensor *tok_embd, *output_norm, *output_w, *output_b;
    gx_layer layers[GX_MAX_LAYERS];

    es_tok *tok;         // native tokenizer
    int    n_past;       // physical KV fill (slots used)
    int    pos_base;     // absolute position of physical slot 0 (sliding window)
    float *logits;       // n_vocab

    es_gx_sampling samp;          // sampler config
    float   *work;                // n_vocab scratch for sampling
    int32_t  recent[1024];        // ring of recent token ids (repeat penalty)
    int      recent_n;            // total appended (ring index = recent_n % 1024)
    atomic_bool cancel;           // set from any thread to stop generation
};

// ── GGUF helpers ─────────────────────────────────────────────────────────────

static int64_t gx_find(const struct gguf_context *g, const char *fmt, const char *arch) {
    char key[160]; snprintf(key, sizeof(key), fmt, arch); return gguf_find_key(g, key);
}
static uint32_t gx_u32(const struct gguf_context *g, const char *fmt, const char *arch, uint32_t def) {
    int64_t id = gx_find(g, fmt, arch); return id < 0 ? def : gguf_get_val_u32(g, id);
}
static float gx_f32(const struct gguf_context *g, const char *fmt, const char *arch, float def) {
    int64_t id = gx_find(g, fmt, arch); return id < 0 ? def : gguf_get_val_f32(g, id);
}
static struct ggml_tensor *gx_w(es_gx_model *m, const char *fmt, ...) {
    char name[128]; va_list ap; va_start(ap, fmt); vsnprintf(name, sizeof(name), fmt, ap); va_end(ap);
    for (int s = 0; s < m->n_shards; s++) {
        if (!m->ctx_w_arr[s]) continue;
        struct ggml_tensor *t = ggml_get_tensor(m->ctx_w_arr[s], name);
        if (t) return t;
    }
    return NULL;
}
static es_gx_arch gx_detect_arch(const char *n) {
    if (!strcmp(n, "llama"))  return ES_GX_ARCH_LLAMA;
    if (!strcmp(n, "qwen2"))  return ES_GX_ARCH_QWEN2;
    if (!strcmp(n, "gemma"))  return ES_GX_ARCH_GEMMA;
    if (!strcmp(n, "gemma2")) return ES_GX_ARCH_GEMMA2;
    return ES_GX_ARCH_UNKNOWN;
}

static struct ggml_cgraph *gx_build(es_gx_model *m, struct ggml_context *ctx,
                                    int n_tok, int n_past,
                                    struct ggml_tensor **in_tok,
                                    struct ggml_tensor **in_pos,
                                    struct ggml_tensor **in_mask);

// ── Load ─────────────────────────────────────────────────────────────────────

// Build the path of shard `idx` (1-based) given a `-NNNNN-of-MMMMM.gguf` path.
static bool gx_shard_path(const char *base, int idx, int count, char *out, size_t cap) {
    const char *p = strstr(base, "-of-");
    if (!p) return false;
    // find the start of the first number: 5 digits before "-of-"
    const char *num = p - 5;
    if (num < base || *(num - 1) != '-') return false;
    size_t prefix = (size_t)(num - base);
    snprintf(out, cap, "%.*s%05d-of-%05d.gguf", (int)prefix, base, idx, count);
    return true;
}

es_gx_model *es_gx_load(const char *path, int n_ctx, int kv_quant) {
    es_gx_model *m = calloc(1, sizeof(*m));
    if (!m) return NULL;

    struct gguf_init_params gp = { .no_alloc = true, .ctx = &m->ctx_w_arr[0] };
    m->gguf = gguf_init_from_file(path, gp);
    if (!m->gguf) { fprintf(stderr, "[es_gx] gguf parse failed: %s\n", path); free(m); return NULL; }
    m->n_shards = 1;

    int64_t arch_id = gguf_find_key(m->gguf, "general.architecture");
    if (arch_id < 0) { fprintf(stderr, "[es_gx] no general.architecture\n"); goto fail; }
    snprintf(m->arch_name, sizeof(m->arch_name), "%s", gguf_get_val_str(m->gguf, arch_id));
    m->arch = gx_detect_arch(m->arch_name);
    if (m->arch == ES_GX_ARCH_UNKNOWN) {
        fprintf(stderr, "[es_gx] unsupported architecture: %s\n", m->arch_name); goto fail;
    }
    const char *a = m->arch_name;

    m->n_layer     = (int)gx_u32(m->gguf, "%s.block_count", a, 0);
    m->n_embd      = (int)gx_u32(m->gguf, "%s.embedding_length", a, 0);
    m->n_head      = (int)gx_u32(m->gguf, "%s.attention.head_count", a, 0);
    m->n_head_kv   = (int)gx_u32(m->gguf, "%s.attention.head_count_kv", a, m->n_head);
    m->n_ff        = (int)gx_u32(m->gguf, "%s.feed_forward_length", a, 0);
    m->n_ctx_train = (int)gx_u32(m->gguf, "%s.context_length", a, 4096);
    m->f_norm_eps  = gx_f32(m->gguf, "%s.attention.layer_norm_rms_epsilon", a, 1e-5f);
    m->rope_freq_base  = gx_f32(m->gguf, "%s.rope.freq_base", a, 10000.0f);
    m->rope_freq_scale = 1.0f;
    if (m->n_layer <= 0 || m->n_embd <= 0 || m->n_head <= 0 || m->n_layer > GX_MAX_LAYERS) {
        fprintf(stderr, "[es_gx] bad hparams\n"); goto fail;
    }

    int key_len = (int)gx_u32(m->gguf, "%s.attention.key_length", a, 0);
    m->head_dim = key_len > 0 ? key_len : (m->n_embd / m->n_head);
    m->n_rot    = (int)gx_u32(m->gguf, "%s.rope.dimension_count", a, m->head_dim);
    m->n_embd_k_gqa = m->head_dim * m->n_head_kv;
    m->n_embd_v_gqa = m->head_dim * m->n_head_kv;
    m->f_attn_scale = 1.0f / sqrtf((float)m->head_dim);

    switch (m->arch) {
        case ES_GX_ARCH_LLAMA:  m->rope_type=GGML_ROPE_TYPE_NORMAL; m->gated_gelu=false; m->f_embd_scale=1.0f; m->has_post_norm=false; break;
        case ES_GX_ARCH_QWEN2:  m->rope_type=GGML_ROPE_TYPE_NEOX;   m->gated_gelu=false; m->f_embd_scale=1.0f; m->has_post_norm=false; break;
        case ES_GX_ARCH_GEMMA:  m->rope_type=GGML_ROPE_TYPE_NEOX;   m->gated_gelu=true;  m->f_embd_scale=sqrtf((float)m->n_embd); m->has_post_norm=false; break;
        case ES_GX_ARCH_GEMMA2: m->rope_type=GGML_ROPE_TYPE_NEOX;   m->gated_gelu=true;  m->f_embd_scale=sqrtf((float)m->n_embd); m->has_post_norm=true;  break;
        default: goto fail;
    }

    m->n_ctx = n_ctx > 0 ? n_ctx : (m->n_ctx_train < 8192 ? m->n_ctx_train : 8192);
    m->use_flash = true;   // fused flash-attention (set false to use manual path)
    m->kv_type = kv_quant == 1 ? GGML_TYPE_Q8_0 : (kv_quant == 2 ? GGML_TYPE_Q4_0 : GGML_TYPE_F16);
    if (m->kv_type != GGML_TYPE_F16) m->use_flash = false;   // flash needs F16 KV

    // Metal backend.
    m->backend = ggml_backend_metal_init();
    if (!m->backend) { fprintf(stderr, "[es_gx] metal init failed\n"); goto fail; }
    m->buft = ggml_backend_get_default_buffer_type(m->backend);

    // Detect a sharded model (`-00001-of-N`). The first shard carries metadata;
    // each shard's gguf lists only its own tensors. ctx_w_arr[0] already holds
    // shard 0's tensors; open the rest into ctx_w_arr[1..].
    int64_t split_k = gguf_find_key(m->gguf, "split.count");
    int split_count = split_k >= 0 ? (int)gguf_get_val_u16(m->gguf, split_k) : 1;
    if (split_count < 1) split_count = 1;
    if (split_count > GX_MAX_SHARDS) { fprintf(stderr, "[es_gx] too many shards\n"); goto fail; }

    struct gguf_context *shard_gguf[GX_MAX_SHARDS] = { m->gguf };
    char shard_path[GX_MAX_SHARDS][1024];
    snprintf(shard_path[0], 1024, "%s", path);
    m->n_shards = split_count;
    for (int s = 1; s < split_count; s++) {
        if (!gx_shard_path(path, s + 1, split_count, shard_path[s], 1024)) {
            fprintf(stderr, "[es_gx] cannot derive shard %d path\n", s + 1); goto fail;
        }
        struct gguf_init_params sp = { .no_alloc = true, .ctx = &m->ctx_w_arr[s] };
        shard_gguf[s] = gguf_init_from_file(shard_path[s], sp);
        if (!shard_gguf[s]) { fprintf(stderr, "[es_gx] open shard failed: %s\n", shard_path[s]); goto fail; }
    }

    // Allocate device buffers per shard and stream tensor data in.
    void *staging = NULL; size_t cap = 0;
    for (int s = 0; s < m->n_shards; s++) {
        m->buf_w_arr[s] = ggml_backend_alloc_ctx_tensors_from_buft(m->ctx_w_arr[s], m->buft);
        if (!m->buf_w_arr[s]) { free(staging); fprintf(stderr, "[es_gx] weight buffer alloc failed (shard %d)\n", s); goto fail; }
        FILE *f = fopen(shard_path[s], "rb");
        if (!f) { free(staging); fprintf(stderr, "[es_gx] reopen failed: %s\n", shard_path[s]); goto fail; }
        size_t data_off = gguf_get_data_offset(shard_gguf[s]);
        int64_t n_tensors = gguf_get_n_tensors(shard_gguf[s]);
        for (int64_t i = 0; i < n_tensors; i++) {
            const char *tn = gguf_get_tensor_name(shard_gguf[s], i);
            struct ggml_tensor *t = ggml_get_tensor(m->ctx_w_arr[s], tn);
            if (!t) continue;
            size_t off = data_off + gguf_get_tensor_offset(shard_gguf[s], i);
            size_t sz  = gguf_get_tensor_size(shard_gguf[s], i);
            if (sz > cap) { free(staging); staging = malloc(sz); cap = sz; }
            if (!staging) { fclose(f); goto fail; }
            if (fseek(f, (long)off, SEEK_SET) || fread(staging, 1, sz, f) != sz) {
                fclose(f); free(staging); fprintf(stderr, "[es_gx] read failed: %s\n", tn); goto fail;
            }
            ggml_backend_tensor_set(t, staging, 0, sz);
        }
        fclose(f);
        if (s > 0) gguf_free(shard_gguf[s]);   // keep shard 0 (metadata + tokenizer)
    }
    free(staging);

    // Bind weights.
    m->tok_embd    = gx_w(m, "token_embd.weight");
    m->output_norm = gx_w(m, "output_norm.weight");
    m->output_w    = gx_w(m, "output.weight");
    m->output_b    = gx_w(m, "output.bias");
    if (!m->tok_embd || !m->output_norm) { fprintf(stderr, "[es_gx] missing core tensors\n"); goto fail; }
    m->n_vocab = (int)m->tok_embd->ne[1];

    for (int il = 0; il < m->n_layer; il++) {
        gx_layer *L = &m->layers[il];
        L->attn_norm = gx_w(m, "blk.%d.attn_norm.weight", il);
        L->wq = gx_w(m, "blk.%d.attn_q.weight", il);
        L->wk = gx_w(m, "blk.%d.attn_k.weight", il);
        L->wv = gx_w(m, "blk.%d.attn_v.weight", il);
        L->wo = gx_w(m, "blk.%d.attn_output.weight", il);
        L->bq = gx_w(m, "blk.%d.attn_q.bias", il);
        L->bk = gx_w(m, "blk.%d.attn_k.bias", il);
        L->bv = gx_w(m, "blk.%d.attn_v.bias", il);
        L->bo = gx_w(m, "blk.%d.attn_output.bias", il);
        L->ffn_norm = gx_w(m, "blk.%d.ffn_norm.weight", il);
        L->ffn_gate = gx_w(m, "blk.%d.ffn_gate.weight", il);
        L->ffn_up   = gx_w(m, "blk.%d.ffn_up.weight", il);
        L->ffn_down = gx_w(m, "blk.%d.ffn_down.weight", il);
        L->post_attn_norm = gx_w(m, "blk.%d.post_attention_norm.weight", il);
        L->post_ffn_norm  = gx_w(m, "blk.%d.post_ffw_norm.weight", il);
        if (!L->wq || !L->wk || !L->wv || !L->wo || !L->attn_norm ||
            !L->ffn_norm || !L->ffn_gate || !L->ffn_up || !L->ffn_down) {
            fprintf(stderr, "[es_gx] layer %d missing tensors\n", il); goto fail;
        }
    }

    // Resident KV cache (F16 / Q8_0 / Q4_0), its own backend buffer.
    {
        size_t kv_meta = ggml_tensor_overhead() * (2 * m->n_layer + 4);
        struct ggml_init_params kp = { .mem_size = kv_meta, .mem_buffer = NULL, .no_alloc = true };
        m->ctx_kv = ggml_init(kp);
        if (!m->ctx_kv) goto fail;
        for (int il = 0; il < m->n_layer; il++) {
            m->layers[il].k_cache = ggml_new_tensor_2d(m->ctx_kv, m->kv_type, m->n_embd_k_gqa, m->n_ctx);
            m->layers[il].v_cache = ggml_new_tensor_2d(m->ctx_kv, m->kv_type, m->n_embd_v_gqa, m->n_ctx);
        }
        m->buf_kv = ggml_backend_alloc_ctx_tensors_from_buft(m->ctx_kv, m->buft);
        if (!m->buf_kv) { fprintf(stderr, "[es_gx] kv buffer alloc failed\n"); goto fail; }
    }

    m->tok = es_tok_create(m->gguf);   // non-fatal if NULL (forward still works)
    if (!m->tok) fprintf(stderr, "[es_gx] warning: tokenizer unavailable\n");

    m->galloc = ggml_gallocr_new(m->buft);
    m->logits = malloc(sizeof(float) * (size_t)m->n_vocab);
    m->work   = malloc(sizeof(float) * (size_t)m->n_vocab);
    if (!m->galloc || !m->logits || !m->work) goto fail;
    m->n_past = 0;
    m->recent_n = 0;
    m->samp = (es_gx_sampling){ .temp = 0.7f, .top_p = 0.95f, .top_k = 40,
                                .min_p = 0.05f, .repeat_penalty = 1.1f,
                                .repeat_last_n = 64, .seed = 0 };

    // Pre-reserve the compute buffer for a worst-case prefill so the allocator
    // doesn't reallocate mid-session — keeps GPU memory stable token to token.
    {
        int rt = m->n_ctx < 512 ? m->n_ctx : 512;
        size_t mem = ggml_tensor_overhead() * 32768 + ggml_graph_overhead_custom(32768, false);
        struct ggml_init_params ip = { .mem_size = mem, .mem_buffer = NULL, .no_alloc = true };
        struct ggml_context *tmp = ggml_init(ip);
        if (tmp) {
            struct ggml_tensor *a, *b, *c;
            struct ggml_cgraph *gf = gx_build(m, tmp, rt, 0, &a, &b, &c);
            if (gf) ggml_gallocr_reserve(m->galloc, gf);
            ggml_free(tmp);
        }
    }
    return m;

fail:
    es_gx_free(m);
    return NULL;
}

void es_gx_free(es_gx_model *m) {
    if (!m) return;
    if (m->tok) es_tok_free(m->tok);
    free(m->logits);
    free(m->work);
    if (m->galloc) ggml_gallocr_free(m->galloc);
    if (m->buf_kv) ggml_backend_buffer_free(m->buf_kv);
    if (m->ctx_kv) ggml_free(m->ctx_kv);
    for (int s = 0; s < m->n_shards; s++) {
        if (m->buf_w_arr[s]) ggml_backend_buffer_free(m->buf_w_arr[s]);
        if (m->ctx_w_arr[s]) ggml_free(m->ctx_w_arr[s]);
    }
    if (m->gguf)   gguf_free(m->gguf);
    if (m->backend) ggml_backend_free(m->backend);
    free(m);
}

void es_gx_reset(es_gx_model *m) { if (m) { m->n_past = 0; m->pos_base = 0; m->recent_n = 0; } }

// Slide the KV window: drop the `d` oldest physical slots, move the rest to the
// front, and advance pos_base so the remaining tokens keep their absolute RoPE
// positions (no re-rope needed). Works for F16 and quantized caches.
static bool es_gx_kv_shift(es_gx_model *m, int d) {
    if (d <= 0 || d >= m->n_past) return false;
    const int count = m->n_past - d;
    const size_t krow = ggml_row_size(m->kv_type, m->n_embd_k_gqa);
    const size_t vrow = ggml_row_size(m->kv_type, m->n_embd_v_gqa);

    size_t mem = ggml_tensor_overhead() * 8192 + ggml_graph_overhead_custom(8192, false);
    struct ggml_init_params ip = { .mem_size = mem, .mem_buffer = NULL, .no_alloc = true };
    struct ggml_context *ctx = ggml_init(ip);
    if (!ctx) return false;
    struct ggml_cgraph *gf = ggml_new_graph_custom(ctx, 8192, false);

    for (int il = 0; il < m->n_layer; il++) {
        struct ggml_tensor *kc = m->layers[il].k_cache, *vc = m->layers[il].v_cache;
        struct ggml_tensor *ks = ggml_view_2d(ctx, kc, m->n_embd_k_gqa, count, krow, (size_t)d * krow);
        struct ggml_tensor *kt = ggml_new_tensor_2d(ctx, m->kv_type, m->n_embd_k_gqa, count);
        struct ggml_tensor *kd = ggml_view_2d(ctx, kc, m->n_embd_k_gqa, count, krow, 0);
        ggml_build_forward_expand(gf, ggml_cpy(ctx, ggml_cpy(ctx, ks, kt), kd));
        struct ggml_tensor *vs = ggml_view_2d(ctx, vc, m->n_embd_v_gqa, count, vrow, (size_t)d * vrow);
        struct ggml_tensor *vt = ggml_new_tensor_2d(ctx, m->kv_type, m->n_embd_v_gqa, count);
        struct ggml_tensor *vd = ggml_view_2d(ctx, vc, m->n_embd_v_gqa, count, vrow, 0);
        ggml_build_forward_expand(gf, ggml_cpy(ctx, ggml_cpy(ctx, vs, vt), vd));
    }
    bool ok = ggml_gallocr_alloc_graph(m->galloc, gf)
           && ggml_backend_graph_compute(m->backend, gf) == GGML_STATUS_SUCCESS;
    ggml_free(ctx);
    if (ok) { m->n_past = count; m->pos_base += d; }
    return ok;
}

void es_gx_set_sampling(es_gx_model *m, es_gx_sampling s) { if (m) m->samp = s; }

// ── Graph ────────────────────────────────────────────────────────────────────

static struct ggml_tensor *gx_norm(struct ggml_context *c, struct ggml_tensor *x,
                                   struct ggml_tensor *w, float eps) {
    return ggml_mul(c, ggml_rms_norm(c, x, eps), w);
}

static struct ggml_cgraph *gx_build(es_gx_model *m, struct ggml_context *ctx,
                                    int n_tok, int n_past,
                                    struct ggml_tensor **in_tok,
                                    struct ggml_tensor **in_pos,
                                    struct ggml_tensor **in_mask) {
    const int hd = m->head_dim, nh = m->n_head, nkv = m->n_head_kv;
    const int n_kv = n_past + n_tok;
    const size_t krow = ggml_row_size(m->kv_type, m->n_embd_k_gqa);
    const size_t vrow = ggml_row_size(m->kv_type, m->n_embd_v_gqa);

    struct ggml_cgraph *gf = ggml_new_graph_custom(ctx, 32768, false);

    struct ggml_tensor *tok = ggml_new_tensor_1d(ctx, GGML_TYPE_I32, n_tok);
    ggml_set_name(tok, "tok"); ggml_set_input(tok);
    struct ggml_tensor *pos = ggml_new_tensor_1d(ctx, GGML_TYPE_I32, n_tok);
    ggml_set_name(pos, "pos"); ggml_set_input(pos);
    struct ggml_tensor *mask = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, n_kv, GX_PAD(n_tok, 32));
    ggml_set_name(mask, "mask"); ggml_set_input(mask);
    *in_tok = tok; *in_pos = pos; *in_mask = mask;

    struct ggml_tensor *cur = ggml_get_rows(ctx, m->tok_embd, tok);
    if (m->f_embd_scale != 1.0f) cur = ggml_scale(ctx, cur, m->f_embd_scale);
    struct ggml_tensor *inpL = cur;

    for (int il = 0; il < m->n_layer; il++) {
        gx_layer *L = &m->layers[il];

        cur = gx_norm(ctx, inpL, L->attn_norm, m->f_norm_eps);

        struct ggml_tensor *Q = ggml_mul_mat(ctx, L->wq, cur); if (L->bq) Q = ggml_add(ctx, Q, L->bq);
        struct ggml_tensor *K = ggml_mul_mat(ctx, L->wk, cur); if (L->bk) K = ggml_add(ctx, K, L->bk);
        struct ggml_tensor *V = ggml_mul_mat(ctx, L->wv, cur); if (L->bv) V = ggml_add(ctx, V, L->bv);

        Q = ggml_reshape_3d(ctx, Q, hd, nh,  n_tok);
        K = ggml_reshape_3d(ctx, K, hd, nkv, n_tok);
        V = ggml_reshape_3d(ctx, V, hd, nkv, n_tok);

        Q = ggml_rope_ext(ctx, Q, pos, NULL, m->n_rot, m->rope_type, m->n_ctx_train,
                          m->rope_freq_base, m->rope_freq_scale, 0.0f, 1.0f, 32.0f, 1.0f);
        K = ggml_rope_ext(ctx, K, pos, NULL, m->n_rot, m->rope_type, m->n_ctx_train,
                          m->rope_freq_base, m->rope_freq_scale, 0.0f, 1.0f, 32.0f, 1.0f);

        // store roped K and raw V into the resident cache at column n_past
        struct ggml_tensor *Kflat = ggml_reshape_2d(ctx, K, m->n_embd_k_gqa, n_tok);
        struct ggml_tensor *Vflat = ggml_reshape_2d(ctx, V, m->n_embd_v_gqa, n_tok);
        struct ggml_tensor *kdst = ggml_view_2d(ctx, L->k_cache, m->n_embd_k_gqa, n_tok, krow, (size_t)n_past * krow);
        struct ggml_tensor *vdst = ggml_view_2d(ctx, L->v_cache, m->n_embd_v_gqa, n_tok, vrow, (size_t)n_past * vrow);
        ggml_build_forward_expand(gf, ggml_cpy(ctx, Kflat, kdst));
        ggml_build_forward_expand(gf, ggml_cpy(ctx, Vflat, vdst));

        // read full K/V [hd, nkv_heads, n_kv] from cache
        struct ggml_tensor *Kc = ggml_view_3d(ctx, L->k_cache, hd, nkv, n_kv,
                                              ggml_row_size(m->kv_type, hd), krow, 0);
        struct ggml_tensor *Vc = ggml_view_3d(ctx, L->v_cache, hd, nkv, n_kv,
                                              ggml_row_size(m->kv_type, hd), vrow, 0);

        // Flash-attention pays off for multi-token prefill (many queries); for
        // single-token decode the manual path is faster (no F16-mask/setup cost).
        const bool flash = m->use_flash && n_tok > 1;
        Q = ggml_permute(ctx, Q, 0, 2, 1, 3);              // [hd, n_tok, nh]
        if (flash) {
            // Fused flash-attention: K/V non-transposed, F16 mask, F32 accumulation.
            struct ggml_tensor *Kf = ggml_permute(ctx, Kc, 0, 2, 1, 3);  // [hd, n_kv, nkv]
            struct ggml_tensor *Vf = ggml_permute(ctx, Vc, 0, 2, 1, 3);  // [hd, n_kv, nkv]
            struct ggml_tensor *m16 = ggml_cast(ctx, mask, GGML_TYPE_F16);
            struct ggml_tensor *fa = ggml_flash_attn_ext(ctx, Q, Kf, Vf, m16,
                                                         m->f_attn_scale, 0.0f, 0.0f);
            ggml_flash_attn_ext_set_prec(fa, GGML_PREC_F32);
            cur = ggml_reshape_2d(ctx, fa, hd * nh, n_tok);   // [n_embd, n_tok]
        } else {
            // Dequantize K/V to F16 for the manual matmuls (cache stays quantized).
            if (m->kv_type != GGML_TYPE_F16) {
                Kc = ggml_cast(ctx, Kc, GGML_TYPE_F16);
                Vc = ggml_cast(ctx, Vc, GGML_TYPE_F16);
            }
            Kc = ggml_permute(ctx, Kc, 0, 2, 1, 3);            // [hd, n_kv, nkv]
            struct ggml_tensor *kq = ggml_mul_mat(ctx, Kc, Q); // [n_kv, n_tok, nh]
            kq = ggml_soft_max_ext(ctx, kq, mask, m->f_attn_scale, 0.0f);
            struct ggml_tensor *Vt = ggml_cont(ctx, ggml_permute(ctx, Vc, 1, 2, 0, 3));
            struct ggml_tensor *kqv = ggml_mul_mat(ctx, Vt, kq);
            cur = ggml_cont_2d(ctx, ggml_permute(ctx, kqv, 0, 2, 1, 3), hd * nh, n_tok);
        }

        cur = ggml_mul_mat(ctx, L->wo, cur); if (L->bo) cur = ggml_add(ctx, cur, L->bo);
        if (L->post_attn_norm) cur = gx_norm(ctx, cur, L->post_attn_norm, m->f_norm_eps);

        struct ggml_tensor *ffn_inp = ggml_add(ctx, cur, inpL);

        cur = gx_norm(ctx, ffn_inp, L->ffn_norm, m->f_norm_eps);
        struct ggml_tensor *g = ggml_mul_mat(ctx, L->ffn_gate, cur);
        struct ggml_tensor *u = ggml_mul_mat(ctx, L->ffn_up,   cur);
        cur = m->gated_gelu ? ggml_geglu_split(ctx, g, u) : ggml_swiglu_split(ctx, g, u);
        cur = ggml_mul_mat(ctx, L->ffn_down, cur);
        if (L->post_ffn_norm) cur = gx_norm(ctx, cur, L->post_ffn_norm, m->f_norm_eps);

        inpL = ggml_add(ctx, cur, ffn_inp);
    }

    struct ggml_tensor *last = ggml_cont(ctx,
        ggml_view_2d(ctx, inpL, m->n_embd, 1, inpL->nb[1], (size_t)(n_tok - 1) * inpL->nb[1]));
    cur = gx_norm(ctx, last, m->output_norm, m->f_norm_eps);
    cur = ggml_mul_mat(ctx, m->output_w ? m->output_w : m->tok_embd, cur);
    if (m->output_b) cur = ggml_add(ctx, cur, m->output_b);
    ggml_set_name(cur, "logits"); ggml_set_output(cur);
    ggml_build_forward_expand(gf, cur);
    return gf;
}

// ── Eval ─────────────────────────────────────────────────────────────────────

const float *es_gx_eval(es_gx_model *m, const int32_t *tokens, int n_tok, int n_past) {
    if (!m || !tokens || n_tok <= 0) return NULL;
    if (n_tok > m->n_ctx) { fprintf(stderr, "[es_gx] batch larger than context\n"); return NULL; }

    // Sliding window: if appending would overflow, drop the oldest quarter so
    // long chats keep going instead of stopping at n_ctx.
    if (n_past + n_tok > m->n_ctx) {
        int need = (n_past + n_tok) - m->n_ctx;
        int d = need + m->n_ctx / 4;
        if (d > n_past) d = n_past - 1;
        if (n_past == m->n_past && es_gx_kv_shift(m, d)) {
            n_past = m->n_past;   // shifted; continue at the new fill
        } else {
            fprintf(stderr, "[es_gx] context overflow (shift unavailable)\n");
            return NULL;
        }
    }

    size_t mem = ggml_tensor_overhead() * 32768 + ggml_graph_overhead_custom(32768, false);
    struct ggml_init_params ip = { .mem_size = mem, .mem_buffer = NULL, .no_alloc = true };
    struct ggml_context *ctx = ggml_init(ip);
    if (!ctx) return NULL;

    struct ggml_tensor *t_tok, *t_pos, *t_mask;
    struct ggml_cgraph *gf = gx_build(m, ctx, n_tok, n_past, &t_tok, &t_pos, &t_mask);
    if (!gf || !ggml_gallocr_alloc_graph(m->galloc, gf)) {
        fprintf(stderr, "[es_gx] graph alloc failed\n"); ggml_free(ctx); return NULL;
    }

    int32_t *pos = malloc(sizeof(int32_t) * n_tok);
    for (int i = 0; i < n_tok; i++) pos[i] = m->pos_base + n_past + i;   // absolute
    ggml_backend_tensor_set(t_tok, tokens, 0, sizeof(int32_t) * n_tok);
    ggml_backend_tensor_set(t_pos, pos, 0, sizeof(int32_t) * n_tok);
    free(pos);

    const int n_kv = n_past + n_tok;
    const int n_q  = GX_PAD(n_tok, 32);
    float *mask = malloc(sizeof(float) * (size_t)n_kv * n_q);
    for (int i = 0; i < n_q; i++)
        for (int j = 0; j < n_kv; j++)
            mask[(size_t)i * n_kv + j] = (i < n_tok && j <= n_past + i) ? 0.0f : -INFINITY;
    ggml_backend_tensor_set(t_mask, mask, 0, sizeof(float) * (size_t)n_kv * n_q);
    free(mask);

    if (ggml_backend_graph_compute(m->backend, gf) != GGML_STATUS_SUCCESS) {
        fprintf(stderr, "[es_gx] compute failed\n"); ggml_free(ctx); return NULL;
    }

    struct ggml_tensor *logits = ggml_graph_get_tensor(gf, "logits");
    ggml_backend_tensor_get(logits, m->logits, 0, sizeof(float) * (size_t)m->n_vocab);

    // record tokens for repeat-penalty (ring buffer)
    for (int i = 0; i < n_tok; i++) m->recent[(m->recent_n + i) & 1023] = tokens[i];
    m->recent_n += n_tok;

    m->n_past = n_past + n_tok;
    ggml_free(ctx);
    return m->logits;
}

const float *es_gx_forward(es_gx_model *m, const int32_t *tokens, int n_tok) {
    es_gx_reset(m);
    return es_gx_eval(m, tokens, n_tok, 0);
}

// ── Sampling ─────────────────────────────────────────────────────────────────

static uint64_t g_rng = 0x853c49e6748fea9bULL;
static double rng_next(void) {            // xorshift -> [0,1)
    g_rng ^= g_rng << 13; g_rng ^= g_rng >> 7; g_rng ^= g_rng << 17;
    return (double)(g_rng >> 11) / 9007199254740992.0;
}

typedef struct { int id; float p; } gx_cand;
static int cmp_cand(const void *a, const void *b) {
    float d = ((const gx_cand*)b)->p - ((const gx_cand*)a)->p;
    return d > 0 ? 1 : (d < 0 ? -1 : 0);
}

static int gx_sample(es_gx_model *m, const float *logits) {
    const int n = m->n_vocab;
    const es_gx_sampling s = m->samp;
    float *w = m->work;
    memcpy(w, logits, sizeof(float) * (size_t)n);

    // repeat penalty over the last repeat_last_n tokens
    if (s.repeat_penalty != 1.0f && s.repeat_last_n > 0) {
        int look = s.repeat_last_n < m->recent_n ? s.repeat_last_n : m->recent_n;
        for (int i = 0; i < look; i++) {
            int idx = (m->recent_n - 1 - i) & 1023;
            int t = m->recent[idx];
            if (t >= 0 && t < n) w[t] = w[t] > 0 ? w[t] / s.repeat_penalty : w[t] * s.repeat_penalty;
        }
    }

    if (s.temp <= 0.0f) {                  // greedy
        int b = 0; for (int i = 1; i < n; i++) if (w[i] > w[b]) b = i; return b;
    }

    // candidates sorted desc; top-k prefilter
    int K = s.top_k > 0 && s.top_k < n ? s.top_k : (n < 512 ? n : 512);
    gx_cand *c = malloc(sizeof(gx_cand) * n);
    for (int i = 0; i < n; i++) { c[i].id = i; c[i].p = w[i]; }
    qsort(c, n, sizeof(gx_cand), cmp_cand);

    float maxl = c[0].p, sum = 0.0f;
    for (int i = 0; i < K; i++) { c[i].p = expf((c[i].p - maxl) / s.temp); sum += c[i].p; }
    for (int i = 0; i < K; i++) c[i].p /= sum;

    // min-p: drop tokens below min_p * p(top)
    float pmax = c[0].p, thresh = s.min_p > 0 ? s.min_p * pmax : 0.0f;
    // top-p (nucleus) + min-p cutoff
    float cum = 0.0f; int last = K - 1;
    for (int i = 0; i < K; i++) {
        if (c[i].p < thresh) { last = i - 1; break; }
        cum += c[i].p;
        if (s.top_p < 1.0f && cum >= s.top_p) { last = i; break; }
    }
    if (last < 0) last = 0;

    float norm = 0.0f; for (int i = 0; i <= last; i++) norm += c[i].p;
    double r = rng_next() * norm, acc = 0.0;
    int pick = c[0].id;
    for (int i = 0; i <= last; i++) { acc += c[i].p; if (r <= acc) { pick = c[i].id; break; } }
    free(c);
    return pick;
}

// ── High-level generation ────────────────────────────────────────────────────

int es_gx_ingest(es_gx_model *m, const char *text, bool add_bos, bool parse_special) {
    if (!m || !m->tok || !text) return -1;
    int32_t *toks = malloc(sizeof(int32_t) * m->n_ctx);
    if (!toks) return -1;
    int n_tok = es_tok_encode(m->tok, text, toks, m->n_ctx - m->n_past, add_bos, parse_special);
    if (n_tok <= 0) { free(toks); return -1; }
    const float *logits = es_gx_eval(m, toks, n_tok, m->n_past);
    free(toks);
    return logits ? 0 : -1;
}

// Byte length of the longest complete UTF-8 prefix of buf[0..n).
// A multi-byte codepoint may be split across tokens (byte-level BPE), so we
// only ever hand the callback whole, valid UTF-8 — otherwise the host decoder
// turns the partial bytes into U+FFFD (the "" garbage).
static int gx_utf8_complete(const unsigned char *b, int n) {
    int i = 0;
    while (i < n) {
        unsigned char c = b[i];
        int len = (c < 0x80) ? 1
                : ((c >> 5) == 0x6) ? 2
                : ((c >> 4) == 0xE) ? 3
                : ((c >> 3) == 0x1E) ? 4 : 1;
        if (i + len > n) break;   // incomplete trailing sequence: hold it back
        i += len;
    }
    return i;
}

int es_gx_generate_stream(es_gx_model *m, int max_tokens, es_gx_token_cb cb, void *ud) {
    if (!m || !m->tok) return -1;
    if (m->samp.seed) g_rng = (uint64_t)m->samp.seed * 2654435761u + 1;
    atomic_store(&m->cancel, false);
    const float *logits = m->logits;   // set by the last ingest/eval
    int produced = 0;
    char piece[64];
    char pend[256]; int plen = 0;      // buffer for split UTF-8 sequences
    for (int g = 0; g < max_tokens && m->n_past < m->n_ctx; g++) {
        if (atomic_load(&m->cancel)) break;
        int id = gx_sample(m, logits);
        if (es_gx_token_is_eog(m, id)) break;
        int k = es_tok_decode(m->tok, id, piece, sizeof(piece));
        if (k > 0 && cb) {
            // flush first if the new bytes wouldn't fit (keeps pend bounded)
            if (plen + k > (int)sizeof(pend) - 1) {
                pend[plen] = 0; cb(pend, ud); plen = 0;
            }
            memcpy(pend + plen, piece, k); plen += k;
            int good = gx_utf8_complete((const unsigned char *)pend, plen);
            if (good > 0) {
                char saved = pend[good];
                pend[good] = 0; cb(pend, ud); pend[good] = saved;
                memmove(pend, pend + good, plen - good); plen -= good;
            }
        }
        produced++;
        logits = es_gx_eval(m, &id, 1, m->n_past);
        if (!logits) break;
    }
    if (plen > 0 && cb) { pend[plen] = 0; cb(pend, ud); }   // flush remainder
    return produced;
}

int es_gx_n_past(const es_gx_model *m) { return m ? m->n_past : 0; }

void es_gx_cancel(es_gx_model *m) { if (m) atomic_store(&m->cancel, true); }

es_gx_arch es_gx_probe_arch(const char *path) {
    struct gguf_init_params gp = { .no_alloc = true, .ctx = NULL };
    struct gguf_context *g = gguf_init_from_file(path, gp);
    if (!g) return ES_GX_ARCH_UNKNOWN;
    es_gx_arch a = ES_GX_ARCH_UNKNOWN;
    int64_t id = gguf_find_key(g, "general.architecture");
    if (id >= 0) a = gx_detect_arch(gguf_get_val_str(g, id));
    gguf_free(g);
    return a;
}

int es_gx_generate(es_gx_model *m, const char *prompt, int max_tokens,
                   float temp, float top_p, bool add_bos, bool parse_special,
                   es_gx_token_cb cb, void *ud) {
    if (!m) return -1;
    m->samp.temp = temp; m->samp.top_p = top_p;
    es_gx_reset(m);
    if (es_gx_ingest(m, prompt, add_bos, parse_special) != 0) return -1;
    return es_gx_generate_stream(m, max_tokens, cb, ud);
}

int es_gx_chat(es_gx_model *m, const char *system, const char *user, int max_tokens,
               float temp, float top_p, es_gx_token_cb cb, void *ud) {
    if (!m || !user) return -1;
    char *p = malloc(1 << 16);
    if (!p) return -1;
    es_gx_arch a = m->arch;
    if (a == ES_GX_ARCH_QWEN2) {
        snprintf(p, 1 << 16,
                 "<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n",
                 system && system[0] ? system : "You are a helpful assistant.", user);
    } else { // llama3
        if (system && system[0])
            snprintf(p, 1 << 16,
                "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n%s<|eot_id|>"
                "<|start_header_id|>user<|end_header_id|>\n\n%s<|eot_id|>"
                "<|start_header_id|>assistant<|end_header_id|>\n\n", system, user);
        else
            snprintf(p, 1 << 16,
                "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n%s<|eot_id|>"
                "<|start_header_id|>assistant<|end_header_id|>\n\n", user);
    }
    int r = es_gx_generate(m, p, max_tokens, temp, top_p, false, true, cb, ud);
    free(p);
    return r;
}

// ── Tokenizer wrappers ───────────────────────────────────────────────────────

int es_gx_encode(es_gx_model *m, const char *text, int32_t *out, int max_out,
                 bool add_bos, bool parse_special) {
    if (!m || !m->tok) return -1;
    return es_tok_encode(m->tok, text, out, max_out, add_bos, parse_special);
}
int es_gx_decode(es_gx_model *m, int32_t id, char *buf, int buf_size) {
    if (!m || !m->tok) { if (buf_size) buf[0] = 0; return 0; }
    return es_tok_decode(m->tok, id, buf, buf_size);
}
int  es_gx_bos(const es_gx_model *m) { return m && m->tok ? es_tok_bos(m->tok) : -1; }
int  es_gx_eos(const es_gx_model *m) { return m && m->tok ? es_tok_eos(m->tok) : -1; }
bool es_gx_token_is_eog(const es_gx_model *m, int32_t id) {
    return m && m->tok && es_tok_is_eog(m->tok, id);
}
bool es_gx_is_spm(const es_gx_model *m) { return m && m->tok && es_tok_is_spm(m->tok); }

// ── Introspection ────────────────────────────────────────────────────────────

int         es_gx_n_vocab(const es_gx_model *m)     { return m ? m->n_vocab : 0; }
int         es_gx_n_embd(const es_gx_model *m)       { return m ? m->n_embd : 0; }
int         es_gx_n_ctx(const es_gx_model *m)        { return m ? m->n_ctx : 0; }
int         es_gx_n_ctx_train(const es_gx_model *m)  { return m ? m->n_ctx_train : 0; }
es_gx_arch  es_gx_get_arch(const es_gx_model *m)     { return m ? m->arch : ES_GX_ARCH_UNKNOWN; }
const char *es_gx_arch_name(const es_gx_model *m)    { return m ? m->arch_name : "?"; }
