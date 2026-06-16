// test_gx.c — correctness gate + benchmark for the native ggml engine (es_gx).
//
// 1. Prefill correctness: feed identical tokens to es_gx and to libllama,
//    compare last-token logits (argmax + cosine).
// 2. KV-cache correctness: greedy-generate N tokens with both engines and
//    confirm the token sequences match exactly (greedy is deterministic).
// 3. Throughput: report prefill and decode tokens/sec for es_gx.
//
// Usage: ./test_gx <model.gguf> [prompt] [n_gen]

#include "es_gx.h"
#include "llama.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define GREEN "\033[32m"
#define RED   "\033[31m"
#define RESET "\033[0m"
#define BOLD  "\033[1m"

static int argmax(const float *v, int n) {
    int b = 0; for (int i = 1; i < n; i++) if (v[i] > v[b]) b = i; return b;
}
static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <model.gguf> [prompt] [n_gen]\n", argv[0]); return 1; }
    const char *path   = argv[1];
    const char *prompt = argc > 2 ? argv[2] : "The capital of France is";
    int n_gen = argc > 3 ? atoi(argv[3]) : 32;

    printf(BOLD "es_gx correctness + throughput gate\n" RESET
           "model: %s\nprompt: \"%s\" | n_gen=%d\n\n", path, prompt, n_gen);

    // ── reference: libllama (run first, then fully freed so big models fit) ───
    llama_backend_init();
    struct llama_model *lm = llama_model_load_from_file(path, llama_model_default_params());
    if (!lm) { fprintf(stderr, RED "[FATAL]" RESET " llama load\n"); return 1; }
    const struct llama_vocab *vocab = llama_model_get_vocab(lm);
    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = 1024; cp.n_batch = 1024;
    struct llama_context *lc = llama_init_from_model(lm, cp);
    int n_vocab = llama_vocab_n_tokens(vocab);

    int32_t toks[512];
    int n_tok = llama_tokenize(vocab, prompt, (int)strlen(prompt), toks, 512, true, true);
    if (n_tok <= 0) { fprintf(stderr, RED "[FATAL]" RESET " tokenize\n"); return 1; }
    printf("prompt tokens: %d\n", n_tok);

    struct llama_batch b = llama_batch_init(n_tok, 0, 1);
    for (int i = 0; i < n_tok; i++) { b.token[i]=toks[i]; b.pos[i]=i; b.n_seq_id[i]=1; b.seq_id[i][0]=0; b.logits[i]=(i==n_tok-1); }
    b.n_tokens = n_tok;
    if (llama_decode(lc, b) != 0) { fprintf(stderr, RED "[FATAL]" RESET " llama prefill\n"); return 1; }
    float *ref = malloc(sizeof(float)*n_vocab);
    memcpy(ref, llama_get_logits_ith(lc, n_tok-1), sizeof(float)*n_vocab);

    // llama greedy generation; capture ids + decoded pieces. Time the whole loop
    // wall-clock (llama_decode is async on Metal; the next get_logits forces the
    // sync), then force a final sync so all n_gen decodes are counted.
    int32_t llama_gen[256]; int ll_past = n_tok;
    char gen_text[8192]; gen_text[0] = 0;
    double t_ll0 = now_s();
    for (int g = 0; g < n_gen; g++) {
        int tk = argmax(llama_get_logits_ith(lc, -1), n_vocab);
        llama_gen[g] = tk;
        char p[64] = {0}; llama_token_to_piece(vocab, tk, p, 63, 0, true);
        strncat(gen_text, p, sizeof(gen_text) - strlen(gen_text) - 1);
        struct llama_batch sb = llama_batch_init(1, 0, 1);
        sb.token[0]=tk; sb.pos[0]=ll_past; sb.n_seq_id[0]=1; sb.seq_id[0][0]=0; sb.logits[0]=1; sb.n_tokens=1;
        llama_decode(lc, sb);
        llama_batch_free(sb); ll_past++;
    }
    llama_synchronize(lc);
    double ll_dec_tps = n_gen / (now_s() - t_ll0);
    int a_ref = argmax(ref, n_vocab);
    char pr[64] = {0}; llama_token_to_piece(vocab, a_ref, pr, 63, 0, true);

    llama_batch_free(b);
    llama_free(lc);
    llama_model_free(lm);
    llama_backend_free();
    printf("(reference computed; llama freed)\n");

    // ── ours: es_gx (now the only model resident) ────────────────────────────
    es_gx_model *gm = es_gx_load(path, 1024, 0);
    if (!gm) { fprintf(stderr, RED "[FATAL]" RESET " es_gx load\n"); return 1; }
    printf("es_gx arch=%s n_vocab=%d n_ctx=%d head_dim=%d\n\n",
           es_gx_arch_name(gm), es_gx_n_vocab(gm), es_gx_n_ctx(gm), 0);
    if (es_gx_n_vocab(gm) != n_vocab) { fprintf(stderr, RED "[FATAL]" RESET " vocab mismatch\n"); return 1; }

    // prefill (timed)
    double t0 = now_s();
    const float *ours = es_gx_eval(gm, toks, n_tok, 0);
    double t_prefill = now_s() - t0;
    if (!ours) { fprintf(stderr, RED "[FATAL]" RESET " es_gx prefill\n"); return 1; }

    // prefill logits comparison (a_ref already computed before freeing llama)
    int a_ours = argmax(ours, n_vocab);
    double dot=0,nr=0,no=0,maxd=0;
    for (int i=0;i<n_vocab;i++){ double d=(double)ref[i]-ours[i]; if(fabs(d)>maxd)maxd=fabs(d);
        dot+=(double)ref[i]*ours[i]; nr+=(double)ref[i]*ref[i]; no+=(double)ours[i]*ours[i]; }
    double cosine = dot/(sqrt(nr)*sqrt(no)+1e-9);

    // es_gx greedy generation (timed, incremental decode)
    int32_t gx_gen[256]; int gx_past = n_tok;
    double t_dec = 0;
    const float *cur_logits = ours;   // prefill logits give the first token
    for (int g = 0; g < n_gen; g++) {
        int tk = argmax(cur_logits, n_vocab);
        gx_gen[g] = tk;
        double s = now_s();
        cur_logits = es_gx_eval(gm, &tk, 1, gx_past);
        t_dec += now_s() - s;
        gx_past++;
        if (!cur_logits) { fprintf(stderr, RED "[FATAL]" RESET " es_gx decode\n"); return 1; }
    }

    // ── compare ──────────────────────────────────────────────────────────────
    printf("--- prefill (n_vocab=%d) ---\n", n_vocab);
    printf("  argmax ref=%d(\"%s\")  ours=%d  cosine=%.6f  max|d|=%.4f\n",
           a_ref, pr, a_ours, cosine, maxd);

    int match = 0; for (int g=0; g<n_gen; g++) { if (gx_gen[g]==llama_gen[g]) match++; else break; }
    printf("\n--- greedy generation match (KV cache, ids vs llama) ---\n");
    printf("  matching leading tokens: %d / %d\n", match, n_gen);
    printf("  text (greedy): \"%s\"\n", gen_text);

    double gx_dec_tps = n_gen / t_dec;
    printf("\n--- throughput (Metal) ---\n");
    printf("  es_gx   decode: %.1f tok/s   (prefill %.1f tok/s)\n", gx_dec_tps, n_tok/t_prefill);
    printf("  llama   decode: %.1f tok/s\n", ll_dec_tps);
    printf("  es_gx / llama : %.0f%% of reference decode speed\n", 100.0 * gx_dec_tps / ll_dec_tps);

    int pass = (a_ref==a_ours) && (cosine>0.999) && (match==n_gen);
    printf("\n%s\n", pass ? GREEN "  [PASS] es_gx matches llama.cpp (logits + greedy + KV cache)" RESET
                          : RED   "  [FAIL] divergence" RESET);

    free(ref); es_gx_free(gm);
    return pass ? 0 : 1;
}
