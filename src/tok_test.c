// tok_test.c — validate es_tok against llama.cpp's tokenizer on a corpus.
// Usage: ./tok_test <model.gguf>

#include "es_tok.h"
#include "llama.h"
#include "gguf.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define GREEN "\033[32m"
#define RED   "\033[31m"
#define RESET "\033[0m"

static const char *CORPUS[] = {
    "The capital of France is Paris.",
    "Hello, world!",
    "def foo(x):\n    return x * 2  # double it",
    "I don't think it's 1234567 apples, you're right.",
    "Multiple   spaces and\ttabs\nand\n\nnewlines",
    "Numbers: 42, 3.14159, 1000000 and -5",
    "Mix3d alpha123num CamelCase snake_case",
    "Café résumé naïve jalapeño",
    "Symbols: @#$%^&*()_+-=[]{}|;:,.<>?/",
    "https://example.com/path?q=1&x=2",
    "ÀÉÎ emoji-free but accented",
    "a  b   c    d",
};

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <model.gguf>\n", argv[0]); return 1; }
    const char *path = argv[1];

    llama_backend_init();
    struct llama_model *lm = llama_model_load_from_file(path, llama_model_default_params());
    if (!lm) { fprintf(stderr, RED "[FATAL]" RESET " llama load\n"); return 1; }
    const struct llama_vocab *vocab = llama_model_get_vocab(lm);

    struct gguf_init_params gp = { .no_alloc = true, .ctx = NULL };
    struct gguf_context *g = gguf_init_from_file(path, gp);
    es_tok *t = es_tok_create(g);
    if (!t) { fprintf(stderr, RED "[FATAL]" RESET " es_tok create\n"); return 1; }

    int n_cases = sizeof(CORPUS) / sizeof(CORPUS[0]);
    int pass = 0;
    for (int c = 0; c < n_cases; c++) {
        const char *s = CORPUS[c];
        int32_t ref[1024], ours[1024];
        int nr = llama_tokenize(vocab, s, (int)strlen(s), ref, 1024, true, true);
        int no = es_tok_encode(t, s, ours, 1024, es_tok_add_bos_default(t), true);

        int ok = (nr == no);
        int firstdiff = -1;
        if (ok) for (int i = 0; i < nr; i++) if (ref[i] != ours[i]) { ok = 0; firstdiff = i; break; }
        if (ok) pass++;

        printf("%s case %2d (%d tok): %.40s\n", ok ? GREEN "[ok]" RESET : RED "[XX]" RESET, c, nr, s);
        if (!ok) {
            printf("     ref (%d): ", nr); for (int i=0;i<nr;i++) printf("%d ", ref[i]); printf("\n");
            printf("    ours (%d): ", no); for (int i=0;i<no;i++) printf("%d ", ours[i]); printf("\n");
            if (firstdiff >= 0) printf("     first diff @ %d: ref=%d ours=%d\n", firstdiff, ref[firstdiff], ours[firstdiff]);
        }
    }

    printf("\n%s\n", pass==n_cases ? GREEN "  [PASS] tokenizer matches llama.cpp" RESET
                                   : RED   "  [PARTIAL] some cases differ" RESET);
    printf("  %d / %d cases identical\n", pass, n_cases);

    es_tok_free(t); gguf_free(g);
    llama_model_free(lm); llama_backend_free();
    return pass==n_cases ? 0 : 1;
}
