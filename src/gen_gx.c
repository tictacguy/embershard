// gen_gx.c — standalone multi-turn generation with es_gx (NO libllama).
// Validates the stateful primitives (ingest + generate_stream) and KV reuse:
// the first turn is a full prompt, later turns are continuations (cheap append).
//
// Usage: ./gen_gx <model.gguf> "turn1" ["turn2" "turn3" ...]

#include "es_gx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
static void on_piece(const char *p, void *ud) { (void)ud; fputs(p, stdout); fflush(stdout); }

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <model.gguf> \"turn1\" [\"turn2\" ...]\n", argv[0]); return 1; }
    const char *path = argv[1];

    int ctx = getenv("ES_CTX") ? atoi(getenv("ES_CTX")) : 4096;   // small = test sliding window
    int kvq = getenv("ES_KV")  ? atoi(getenv("ES_KV"))  : 0;      // 0=F16 1=Q8_0 2=Q4_0
    es_gx_model *m = es_gx_load(path, ctx, kvq);
    if (!m) { fprintf(stderr, "load failed\n"); return 1; }
    int qwen = (es_gx_get_arch(m) == ES_GX_ARCH_QWEN2);
    fprintf(stderr, "[arch=%s, %d turns]\n", es_gx_arch_name(m), argc - 2);

    char buf[8192];
    for (int turn = 2; turn < argc; turn++) {
        const char *user = argv[turn];
        int first = (turn == 2);
        if (qwen) {
            if (first) snprintf(buf, sizeof(buf), "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n", user);
            else       snprintf(buf, sizeof(buf), "<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n", user);
        } else {
            if (first) snprintf(buf, sizeof(buf),
                "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n%s<|eot_id|>"
                "<|start_header_id|>assistant<|end_header_id|>\n\n", user);
            else       snprintf(buf, sizeof(buf),
                "<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n%s<|eot_id|>"
                "<|start_header_id|>assistant<|end_header_id|>\n\n", user);
        }
        printf("\n\033[1m> %s\033[0m\n", user);
        double t0 = now_s();
        es_gx_set_sampling(m, (es_gx_sampling){ .temp = 0.0f, .top_p = 1.0f, .top_k = 0,
                                                .min_p = 0.0f, .repeat_penalty = 1.0f,
                                                .repeat_last_n = 0, .seed = 0 });
        if (es_gx_ingest(m, buf, false, true) != 0) { fprintf(stderr, "ingest failed\n"); return 1; }
        int n = es_gx_generate_stream(m, 200, on_piece, NULL);
        printf("\n  [turn %d: %d tok, %.1f tok/s, n_past=%d]\n",
               turn - 1, n, n / (now_s() - t0 + 1e-9), es_gx_n_past(m));
    }
    es_gx_free(m);
    return 0;
}
