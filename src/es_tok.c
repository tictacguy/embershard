// es_tok.c — byte-level BPE tokenizer (GPT-2 family) read from GGUF metadata.
// Mirrors llama.cpp's "llama-bpe" / "qwen2" pre-tokenizers to produce identical
// token IDs, without depending on libllama.

#include "es_tok.h"
#include "gguf.h"
#include "ggml.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ── tiny string->int hashmap (open addressing, FNV-1a) ───────────────────────

typedef struct { const char *key; int val; } hm_ent;
typedef struct { hm_ent *e; int cap; } hmap;

static void hm_init(hmap *h, int n) {
    int cap = 16; while (cap < n * 2) cap <<= 1;
    h->cap = cap; h->e = calloc(cap, sizeof(hm_ent));
}
static uint32_t fnv(const char *s) {
    uint32_t h = 2166136261u;
    for (; *s; s++) { h ^= (unsigned char)*s; h *= 16777619u; }
    return h;
}
static void hm_put(hmap *h, const char *key, int val) {
    uint32_t i = fnv(key) & (h->cap - 1);
    while (h->e[i].key) { if (!strcmp(h->e[i].key, key)) { h->e[i].val = val; return; } i = (i + 1) & (h->cap - 1); }
    h->e[i].key = key; h->e[i].val = val;
}
static int hm_get(const hmap *h, const char *key) {
    uint32_t i = fnv(key) & (h->cap - 1);
    while (h->e[i].key) { if (!strcmp(h->e[i].key, key)) return h->e[i].val; i = (i + 1) & (h->cap - 1); }
    return -1;
}

// ── UTF-8 ────────────────────────────────────────────────────────────────────

static int utf8_dec(const char *s, uint32_t *cp) {
    unsigned char c = (unsigned char)s[0];
    if (c < 0x80) { *cp = c; return 1; }
    if ((c >> 5) == 6)  { *cp = ((c & 0x1f) << 6) | (s[1] & 0x3f); return 2; }
    if ((c >> 4) == 14) { *cp = ((c & 0x0f) << 12) | ((s[1] & 0x3f) << 6) | (s[2] & 0x3f); return 3; }
    *cp = ((c & 0x07) << 18) | ((s[1] & 0x3f) << 12) | ((s[2] & 0x3f) << 6) | (s[3] & 0x3f); return 4;
}
static int utf8_enc(uint32_t cp, char *b) {
    if (cp < 0x80) { b[0] = cp; return 1; }
    if (cp < 0x800) { b[0] = 0xC0 | (cp >> 6); b[1] = 0x80 | (cp & 0x3f); return 2; }
    if (cp < 0x10000) { b[0] = 0xE0 | (cp >> 12); b[1] = 0x80 | ((cp >> 6) & 0x3f); b[2] = 0x80 | (cp & 0x3f); return 3; }
    b[0] = 0xF0 | (cp >> 18); b[1] = 0x80 | ((cp >> 12) & 0x3f); b[2] = 0x80 | ((cp >> 6) & 0x3f); b[3] = 0x80 | (cp & 0x3f); return 4;
}

// ── tokenizer ────────────────────────────────────────────────────────────────

struct es_tok {
    int     n_vocab;
    char  **tokens;        // id -> string (NUL-terminated, byte-level encoded)
    int    *types;
    hmap    tok2id;
    char  **merge_keys;    // "A B"
    int     n_merges;
    hmap    merges;

    char    b2u[256][8];   // byte -> utf8 string
    int     cp2byte[512];  // codepoint -> byte (-1 if none)

    int     bos, eos;
    bool    add_bos_default;
    int     ndig;          // \p{N} grouping: 3 (llama) or 1 (qwen)

    // SPM (SentencePiece) support
    bool    spm;           // true if tokenizer.ggml.model == "llama"
    float  *scores;        // per-token merge score (SPM)
    bool    add_space_prefix;
    int     byte2id[256];  // raw byte -> token id (SPM byte fallback)

    // special tokens (CONTROL / USER_DEFINED)
    int    *spec_ids; int n_spec;
    int     eog[16]; int n_eog;   // all end-of-generation token ids
};

static void build_bytelevel(es_tok *t) {
    for (int i = 0; i < 512; i++) t->cp2byte[i] = -1;
    int used[512] = {0};
    // direct ranges map to themselves
    for (int b = 0; b < 256; b++) {
        int direct = (b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || (b >= 0xAE && b <= 0xFF);
        if (direct) { int n = utf8_enc(b, t->b2u[b]); t->b2u[b][n] = 0; t->cp2byte[b] = b; used[b] = 1; }
    }
    int n = 0;
    for (int b = 0; b < 256; b++) {
        int direct = (b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || (b >= 0xAE && b <= 0xFF);
        if (!direct) { uint32_t cp = 256 + n++; int k = utf8_enc(cp, t->b2u[b]); t->b2u[b][k] = 0; if (cp < 512) t->cp2byte[cp] = b; used[cp] = 1; }
    }
    (void)used;
}

es_tok *es_tok_create(const struct gguf_context *g) {
    es_tok *t = calloc(1, sizeof(*t));
    if (!t) return NULL;

    int64_t k_tokens = gguf_find_key(g, "tokenizer.ggml.tokens");
    int64_t k_merges = gguf_find_key(g, "tokenizer.ggml.merges");
    int64_t k_types  = gguf_find_key(g, "tokenizer.ggml.token_type");
    int64_t k_scores = gguf_find_key(g, "tokenizer.ggml.scores");
    int64_t k_model  = gguf_find_key(g, "tokenizer.ggml.model");
    if (k_tokens < 0) { fprintf(stderr, "[es_tok] no tokens\n"); free(t); return NULL; }

    const char *model = k_model >= 0 ? gguf_get_val_str(g, k_model) : "gpt2";
    t->spm = !strcmp(model, "llama");        // SentencePiece
    if (!t->spm && k_merges < 0) { fprintf(stderr, "[es_tok] BPE without merges\n"); free(t); return NULL; }

    t->n_vocab = (int)gguf_get_arr_n(g, k_tokens);
    t->tokens = malloc(sizeof(char*) * t->n_vocab);
    t->types  = malloc(sizeof(int) * t->n_vocab);
    hm_init(&t->tok2id, t->n_vocab);
    const int32_t *types = k_types >= 0 ? (const int32_t*)gguf_get_arr_data(g, k_types) : NULL;
    for (int i = 0; i < t->n_vocab; i++) {
        t->tokens[i] = strdup(gguf_get_arr_str(g, k_tokens, i));
        t->types[i] = types ? types[i] : 1;
        hm_put(&t->tok2id, t->tokens[i], i);
    }

    if (t->spm) {
        // SPM: per-token scores + byte-fallback map; no merges.
        t->scores = malloc(sizeof(float) * t->n_vocab);
        const float *sc = k_scores >= 0 ? (const float*)gguf_get_arr_data(g, k_scores) : NULL;
        for (int i = 0; i < t->n_vocab; i++) t->scores[i] = sc ? sc[i] : 0.0f;
        const char *hex = "0123456789ABCDEF";
        for (int ch = 0; ch < 256; ch++) {
            char buf[8] = { '<','0','x', hex[ch>>4], hex[ch&15], '>', 0, 0 };
            int id = hm_get(&t->tok2id, buf);
            if (id < 0) { char one[2] = { (char)ch, 0 }; id = hm_get(&t->tok2id, one); }
            t->byte2id[ch] = id;
        }
        t->add_space_prefix = true;
        int64_t kp = gguf_find_key(g, "tokenizer.ggml.add_space_prefix");
        if (kp >= 0) t->add_space_prefix = gguf_get_val_bool(g, kp);
    } else {
        t->n_merges = (int)gguf_get_arr_n(g, k_merges);
        t->merge_keys = malloc(sizeof(char*) * t->n_merges);
        hm_init(&t->merges, t->n_merges);
        for (int i = 0; i < t->n_merges; i++) {
            t->merge_keys[i] = strdup(gguf_get_arr_str(g, k_merges, i));
            hm_put(&t->merges, t->merge_keys[i], i);
        }
        build_bytelevel(t);
    }

    // special tokens
    t->spec_ids = malloc(sizeof(int) * t->n_vocab);
    t->n_spec = 0;
    for (int i = 0; i < t->n_vocab; i++)
        if (t->types[i] == 3 || t->types[i] == 4) t->spec_ids[t->n_spec++] = i;

    int64_t kb = gguf_find_key(g, "tokenizer.ggml.bos_token_id");
    int64_t ke = gguf_find_key(g, "tokenizer.ggml.eos_token_id");
    t->bos = kb >= 0 ? (int)gguf_get_val_u32(g, kb) : -1;
    t->eos = ke >= 0 ? (int)gguf_get_val_u32(g, ke) : -1;

    // End-of-generation set: eos + known end markers among special tokens.
    t->n_eog = 0;
    if (t->eos >= 0) t->eog[t->n_eog++] = t->eos;
    static const char *eog_text[] = {
        "<|eot_id|>", "<|end_of_text|>", "<|im_end|>", "<|endoftext|>", "</s>", "<end_of_turn>"
    };
    for (int s = 0; s < t->n_spec && t->n_eog < 16; s++) {
        const char *txt = t->tokens[t->spec_ids[s]];
        for (size_t e = 0; e < sizeof(eog_text)/sizeof(eog_text[0]); e++) {
            if (!strcmp(txt, eog_text[e])) {
                int id = t->spec_ids[s];
                bool dup = false; for (int k = 0; k < t->n_eog; k++) if (t->eog[k] == id) dup = true;
                if (!dup) t->eog[t->n_eog++] = id;
                break;
            }
        }
    }

    int64_t kpre = gguf_find_key(g, "tokenizer.ggml.pre");
    const char *pre = kpre >= 0 ? gguf_get_val_str(g, kpre) : "llama-bpe";
    bool is_qwen = strstr(pre, "qwen") != NULL;
    t->ndig = is_qwen ? 1 : 3;
    t->add_bos_default = t->spm ? true : !is_qwen;   // SPM & llama3 add BOS; qwen2 doesn't
    int64_t kab = gguf_find_key(g, "tokenizer.ggml.add_bos_token");
    if (kab >= 0) t->add_bos_default = gguf_get_val_bool(g, kab);

    return t;
}

void es_tok_free(es_tok *t) {
    if (!t) return;
    for (int i = 0; i < t->n_vocab; i++) free(t->tokens[i]);
    for (int i = 0; i < t->n_merges; i++) free(t->merge_keys[i]);
    free(t->tokens); free(t->types); free(t->merge_keys); free(t->spec_ids);
    free(t->scores);
    free(t->tok2id.e); free(t->merges.e);
    free(t);
}

int  es_tok_bos(const es_tok *t) { return t->bos; }
int  es_tok_eos(const es_tok *t) { return t->eos; }
bool es_tok_add_bos_default(const es_tok *t) { return t->add_bos_default; }
bool es_tok_is_spm(const es_tok *t) { return t->spm; }
bool es_tok_is_eog(const es_tok *t, int32_t id) {
    for (int i = 0; i < t->n_eog; i++) if (t->eog[i] == id) return true;
    return false;
}

// ── codepoint classification (exact for ASCII; non-ASCII treated as letter) ──

static int is_white(uint32_t c) {
    return c==' '||c=='\t'||c=='\n'||c=='\r'||c=='\v'||c=='\f'||c==0x85||c==0xA0||
           c==0x1680||(c>=0x2000&&c<=0x200A)||c==0x2028||c==0x2029||c==0x202F||c==0x205F||c==0x3000;
}
static int is_nl(uint32_t c) { return c=='\n'||c=='\r'; }
static int is_dig(uint32_t c) { return c>='0'&&c<='9'; }
static int is_let(uint32_t c) {
    if ((c>='A'&&c<='Z')||(c>='a'&&c<='z')) return 1;
    return c>=0x80 && !is_white(c) && !is_dig(c);
}
static uint32_t lc(uint32_t c) { return (c>='A'&&c<='Z') ? c+32 : c; }

// Match one "word" of the pre-tokenizer regex at cp[p..n). Returns #cps (>=1).
static int match_word(const uint32_t *cp, int n, int p, int ndig) {
    // A: contractions  '[sS] '[tT] '[mM] '[dD] '[rR][eE] '[vV][eE] '[lL][lL]
    if (cp[p]=='\'' && p+1<n) {
        uint32_t a = lc(cp[p+1]);
        if (a=='s'||a=='t'||a=='m'||a=='d') return 2;
        if (p+2<n) { uint32_t b = lc(cp[p+2]);
            if ((a=='r'&&b=='e')||(a=='v'&&b=='e')||(a=='l'&&b=='l')) return 3; }
    }
    // B: [^\r\n\p{L}\p{N}]? \p{L}+
    if (!is_nl(cp[p]) && !is_let(cp[p]) && !is_dig(cp[p])) {
        if (p+1<n && is_let(cp[p+1])) { int q=p+1; while(q<n&&is_let(cp[q]))q++; return q-p; }
    } else if (is_let(cp[p])) { int q=p; while(q<n&&is_let(cp[q]))q++; return q-p; }
    // C: \p{N}{1,ndig}
    if (is_dig(cp[p])) { int q=p,c=0; while(q<n&&is_dig(cp[q])&&c<ndig){q++;c++;} return q-p; }
    // D: " "? [^\s\p{L}\p{N}]+ [\r\n]*
    {
        int q=p; if (cp[q]==' ') q++;
        if (q<n && !is_white(cp[q]) && !is_let(cp[q]) && !is_dig(cp[q])) {
            while (q<n && !is_white(cp[q]) && !is_let(cp[q]) && !is_dig(cp[q])) q++;
            while (q<n && is_nl(cp[q])) q++;
            return q-p;
        }
    }
    // E: \s* [\r\n]+
    {
        int q=p; while (q<n && is_white(cp[q]) && !is_nl(cp[q])) q++;
        if (q<n && is_nl(cp[q])) { while (q<n && is_nl(cp[q])) q++; return q-p; }
    }
    // F/G: \s+(?!\S) | \s+
    if (is_white(cp[p])) {
        int q=p; while (q<n && is_white(cp[q])) q++;
        if (q<n) return (q-1>p) ? (q-1)-p : 1;   // followed by non-space: leave last for next word
        return q-p;                               // run to end
    }
    return 1;
}

// BPE-merge one word (byte-encoded UTF-8 in `enc`, length L). Emit token ids.
static int bpe_word(es_tok *t, const char *enc, int L, int32_t *out, int max_out, int idx) {
    // split into single-codepoint symbols
    int soff[1024], slen[1024], ns = 0;
    for (int i = 0; i < L && ns < 1024; ) {
        uint32_t cp; int k = utf8_dec(enc + i, &cp);
        soff[ns] = i; slen[ns] = k; ns++; i += k;
    }
    char key[256];
    for (;;) {
        int best = -1, brank = 0x7fffffff;
        for (int i = 0; i + 1 < ns; i++) {
            int ll = slen[i], rl = slen[i+1];
            if (ll + 1 + rl >= (int)sizeof(key)) continue;
            memcpy(key, enc + soff[i], ll); key[ll] = ' ';
            memcpy(key + ll + 1, enc + soff[i+1], rl); key[ll+1+rl] = 0;
            int r = hm_get(&t->merges, key);
            if (r >= 0 && r < brank) { brank = r; best = i; }
        }
        if (best < 0) break;
        slen[best] += slen[best+1];                       // merge right into left
        for (int j = best+1; j+1 < ns; j++) { soff[j]=soff[j+1]; slen[j]=slen[j+1]; }
        ns--;
    }
    for (int i = 0; i < ns; i++) {
        memcpy(key, enc + soff[i], slen[i]); key[slen[i]] = 0;
        int id = hm_get(&t->tok2id, key);
        if (id < 0) { // fallback: per-codepoint byte tokens (should not happen)
            for (int b = 0; b < slen[i]; ) {
                uint32_t cp; int k = utf8_dec(enc+soff[i]+b, &cp);
                char one[8]; memcpy(one, enc+soff[i]+b, k); one[k]=0;
                int oid = hm_get(&t->tok2id, one);
                if (oid >= 0) { if (idx>=max_out) return -1; out[idx++] = oid; }
                b += k;
            }
            continue;
        }
        if (idx >= max_out) return -1;
        out[idx++] = id;
    }
    return idx;
}

// SentencePiece (SPM) tokenization of a plain text segment: escape spaces to
// U+2581, merge adjacent symbols by highest vocab score, byte-fallback unknowns.
static int spm_segment(es_tok *t, const char *s, int len, int32_t *out, int max_out, int idx) {
    // build escaped text: optional leading "▁", spaces -> "▁" (E2 96 81)
    int ecap = len * 3 + 8;
    char *enc = malloc(ecap);
    int e = 0;
    if (t->add_space_prefix) { enc[e++]='\xe2'; enc[e++]='\x96'; enc[e++]='\x81'; }
    for (int i = 0; i < len; i++) {
        if (s[i] == ' ') { enc[e++]='\xe2'; enc[e++]='\x96'; enc[e++]='\x81'; }
        else enc[e++] = s[i];
    }
    if (e == 0) { free(enc); return idx; }

    // symbols: one per UTF-8 char
    int *soff = malloc(sizeof(int) * (e + 1));
    int *slen = malloc(sizeof(int) * (e + 1));
    int ns = 0;
    for (int i = 0; i < e; ) { uint32_t c; int k = utf8_dec(enc + i, &c); soff[ns]=i; slen[ns]=k; ns++; i += k; }

    char key[512];
    for (;;) {
        int best = -1; float bscore = -1e30f;
        for (int i = 0; i + 1 < ns; i++) {
            int ll = slen[i], rl = slen[i+1];
            if (ll + rl >= (int)sizeof(key)) continue;
            memcpy(key, enc + soff[i], ll); memcpy(key + ll, enc + soff[i+1], rl); key[ll+rl] = 0;
            int id = hm_get(&t->tok2id, key);
            if (id >= 0 && t->scores[id] > bscore) { bscore = t->scores[id]; best = i; }
        }
        if (best < 0) break;
        slen[best] += slen[best+1];
        for (int j = best+1; j+1 < ns; j++) { soff[j]=soff[j+1]; slen[j]=slen[j+1]; }
        ns--;
    }

    for (int i = 0; i < ns; i++) {
        memcpy(key, enc + soff[i], slen[i]); key[slen[i]] = 0;
        int id = hm_get(&t->tok2id, key);
        if (id >= 0) {
            if (idx >= max_out) { free(enc); free(soff); free(slen); return -1; }
            out[idx++] = id;
        } else {
            for (int b = 0; b < slen[i]; b++) {
                int bid = t->byte2id[(unsigned char)enc[soff[i]+b]];
                if (bid >= 0) { if (idx >= max_out) { free(enc); free(soff); free(slen); return -1; } out[idx++] = bid; }
            }
        }
    }
    free(enc); free(soff); free(slen);
    return idx;
}

// Tokenize a plain (no special tokens) text segment.
static int encode_segment(es_tok *t, const char *s, int len, int32_t *out, int max_out, int idx) {
    if (len <= 0) return idx;
    if (t->spm) return spm_segment(t, s, len, out, max_out, idx);
    // decode to codepoints + byte offsets
    int cap = len + 1;
    uint32_t *cp = malloc(sizeof(uint32_t) * cap);
    int *off = malloc(sizeof(int) * (cap + 1));
    int n = 0, i = 0;
    while (i < len) { uint32_t c; int k = utf8_dec(s + i, &c); off[n] = i; cp[n] = c; n++; i += k; }
    off[n] = len;

    char enc[4096];
    int p = 0;
    while (p < n) {
        int k = match_word(cp, n, p, t->ndig);
        int b0 = off[p], b1 = off[p+k];
        // byte-level encode the word
        int e = 0;
        for (int b = b0; b < b1 && e < (int)sizeof(enc) - 8; b++) {
            const char *u = t->b2u[(unsigned char)s[b]];
            int ul = (int)strlen(u); memcpy(enc + e, u, ul); e += ul;
        }
        idx = bpe_word(t, enc, e, out, max_out, idx);
        if (idx < 0) { free(cp); free(off); return -1; }
        p += k;
    }
    free(cp); free(off);
    return idx;
}

int es_tok_encode(es_tok *t, const char *text, int32_t *out, int max_out,
                  bool add_bos, bool parse_special) {
    int idx = 0;
    if (add_bos && t->bos >= 0) { if (idx >= max_out) return -1; out[idx++] = t->bos; }

    int len = (int)strlen(text);
    int base = 0;
    while (base < len) {
        // find earliest special-token match in [base, len)
        int best_pos = len, best_len = 0, best_id = -1;
        if (parse_special) {
            for (int sidx = 0; sidx < t->n_spec; sidx++) {
                int id = t->spec_ids[sidx];
                const char *st = t->tokens[id];
                int sl = (int)strlen(st);
                if (sl == 0) continue;
                const char *m = strstr(text + base, st);
                if (m) {
                    int pos = (int)(m - text);
                    if (pos < best_pos || (pos == best_pos && sl > best_len)) {
                        best_pos = pos; best_len = sl; best_id = id;
                    }
                }
            }
        }
        // encode the gap before the special token
        idx = encode_segment(t, text + base, best_pos - base, out, max_out, idx);
        if (idx < 0) return -1;
        if (best_id < 0) break;
        if (idx >= max_out) return -1;
        out[idx++] = best_id;
        base = best_pos + best_len;
    }
    return idx;
}

int es_tok_decode(es_tok *t, int32_t id, char *buf, int buf_size) {
    if (id < 0 || id >= t->n_vocab) { if (buf_size) buf[0]=0; return 0; }
    const char *s = t->tokens[id];
    int o = 0;
    for (int i = 0; s[i]; ) {
        uint32_t cp; int k = utf8_dec(s + i, &cp); i += k;
        int b = (cp < 512) ? t->cp2byte[cp] : -1;
        if (b >= 0 && o < buf_size - 1) buf[o++] = (char)b;
    }
    if (o < buf_size) buf[o] = 0;
    return o;
}
