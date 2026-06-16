// test_engine.c — integration test for es_api agentic pipeline
// Usage: ./test_engine <model.gguf>
// Tests: es_generate, es_continue, es_orchestrate

#include "es_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GREEN "\033[32m"
#define RED   "\033[31m"
#define RESET "\033[0m"
#define BOLD  "\033[1m"

static int g_pass = 0, g_fail = 0;

static void pass(const char *name) {
    printf(GREEN "  [PASS]" RESET " %s\n", name);
    g_pass++;
}
static void fail(const char *name, const char *reason) {
    printf(RED "  [FAIL]" RESET " %s — %s\n", name, reason);
    g_fail++;
}

// ── Callbacks ──────────────────────────────────────────────────────────────

typedef struct { char buf[65536]; int len; int n_tokens; } Accum;

static void on_token(const char *piece, void *ud) {
    Accum *a = (Accum *)ud;
    int n = (int)strlen(piece);
    if (a->len + n < (int)sizeof(a->buf) - 1) {
        memcpy(a->buf + a->len, piece, (size_t)n);
        a->len += n;
    }
    a->n_tokens++;
    fputs(piece, stdout);
    fflush(stdout);
}
static void on_done(ESStatus st, void *ud) { (void)ud; (void)st; }

static void on_stage(ESAgentStage stage, void *ud) {
    (void)ud;
    const char *names[] = { "planning", "executing", "critiquing" };
    int idx = (int)stage < 3 ? (int)stage : 0;
    printf(BOLD "\n[stage: %s]\n" RESET, names[idx]);
    fflush(stdout);
}

// ── Tests ──────────────────────────────────────────────────────────────────

static void test_generate(ESEngineRef eng) {
    printf("\n-- test: es_generate --\n");
    Accum a = {0};
    ESStatus st = es_generate(eng,
        "You are a helpful assistant. Be brief.",
        "What is 2 + 2? Answer with just the number.",
        64,
        on_token, on_done, &a);
    printf("\n");

    if (st != ES_STATUS_OK) {
        fail("es_generate returns OK", "status != OK");
        return;
    }
    pass("es_generate returns OK");

    if (a.len == 0) {
        fail("es_generate produces output", "empty response");
        return;
    }
    pass("es_generate produces output");

    // Llama-3.2 3B should answer "4"
    if (strstr(a.buf, "4") == NULL) {
        char msg[128];
        snprintf(msg, sizeof(msg), "no '4' in: %.80s", a.buf);
        fail("es_generate correct answer (4)", msg);
    } else {
        pass("es_generate correct answer (4)");
    }
}

static void test_continue(ESEngineRef eng) {
    printf("\n-- test: es_continue (multi-turn) --\n");

    // First turn (re-use already-created context from test_generate)
    Accum a1 = {0};
    ESStatus st = es_generate(eng,
        "You are a helpful assistant. Be brief.",
        "My name is Alice. What is 3 + 3?",
        64,
        on_token, on_done, &a1);
    printf("\n");
    if (st != ES_STATUS_OK) { fail("multi-turn first generate", "status != OK"); return; }

    // Second turn
    Accum a2 = {0};
    st = es_continue(eng, "What is my name?", 64, on_token, on_done, &a2);
    printf("\n");
    if (st != ES_STATUS_OK) { fail("es_continue returns OK", "status != OK"); return; }
    pass("es_continue returns OK");

    if (strstr(a2.buf, "Alice") == NULL && strstr(a2.buf, "alice") == NULL) {
        char msg[128];
        snprintf(msg, sizeof(msg), "no 'Alice' in: %.80s", a2.buf);
        fail("es_continue remembers context (Alice)", msg);
    } else {
        pass("es_continue remembers context (Alice)");
    }
}

static void test_orchestrate(ESEngineRef eng) {
    printf("\n-- test: es_orchestrate (agentic pipeline) --\n");
    Accum a = {0};
    ESStatus st = es_orchestrate(eng,
        NULL,
        "What is the capital of France?",
        256,
        on_stage, on_token, on_done, &a);
    printf("\n");

    if (st != ES_STATUS_OK) {
        fail("es_orchestrate returns OK", "status != OK");
        return;
    }
    pass("es_orchestrate returns OK");

    if (a.len == 0) {
        fail("es_orchestrate produces output", "empty critic response");
        return;
    }
    pass("es_orchestrate produces output");

    if (strstr(a.buf, "Paris") == NULL && strstr(a.buf, "paris") == NULL) {
        char msg[128];
        snprintf(msg, sizeof(msg), "no 'Paris' in: %.80s", a.buf);
        fail("es_orchestrate correct answer (Paris)", msg);
    } else {
        pass("es_orchestrate correct answer (Paris)");
    }
}

// Long-output test: request a lengthy answer and verify generation runs to
// near max_tokens (not cut off early at ~230). Reproduces the app truncation.
static void test_long_output(ESEngineRef eng) {
    printf("\n-- test: long output (truncation check) --\n");
    Accum a = {0};
    const int32_t MAXTOK = 600;
    ESStatus st = es_generate(eng,
        "You are a helpful assistant.",
        "Write a detailed, multi-paragraph essay (at least 500 words) about the "
        "history of the Roman Empire, from its founding to its fall. Include many "
        "specific details, dates, emperors, and events. Do not stop early.",
        MAXTOK,
        on_token, on_done, &a);
    printf("\n");
    printf("  -> generated %d tokens, %d bytes\n", a.n_tokens, a.len);

    if (st != ES_STATUS_OK) { fail("long output returns OK", "status != OK"); return; }
    pass("long output returns OK");

    // If the model genuinely hit EOS that's fine, but a ~230 cutoff while asked
    // for 500+ words signals the truncation bug.
    if (a.n_tokens < 300) {
        char msg[128];
        snprintf(msg, sizeof(msg), "stopped at only %d tokens (expected near %d)",
                 a.n_tokens, MAXTOK);
        fail("long output not truncated early", msg);
    } else {
        pass("long output not truncated early");
    }
}

// ── Entry point ────────────────────────────────────────────────────────────

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <model.gguf>\n", argv[0]);
        return 1;
    }

    printf(BOLD "embershard engine test\n" RESET);
    printf("model: %s\n", argv[1]);

    ESConfig cfg = {
        .model_path  = argv[1],
        .n_gpu_layers = -1,
        .n_ctx        = 4096,
        .n_threads    = 4,
        .temperature  = 0.0f,   // greedy for deterministic tests
        .top_p        = 1.0f,
        .kv_quant     = ES_KV_QUANT_F16,
        .flash_attn   = true,
        .use_mmap     = true,
    };

    printf("\nLoading model...\n");
    ESEngineRef eng = NULL;
    ESStatus st = es_create(&cfg, &eng);
    if (st != ES_STATUS_OK || !eng) {
        fprintf(stderr, RED "[FATAL]" RESET " es_create failed: %d\n", (int)st);
        return 1;
    }
    printf("Model loaded.\n");

    test_generate(eng);
    test_continue(eng);
    test_long_output(eng);
    test_orchestrate(eng);

    es_destroy(eng);

    printf("\n" BOLD "Results: " RESET);
    printf(GREEN "%d passed" RESET ", ", g_pass);
    printf(g_fail > 0 ? RED : RESET);
    printf("%d failed\n" RESET, g_fail);

    return g_fail > 0 ? 1 : 0;
}
