#include "es_engine.h"
#include "es_bench.h"
#include "es_agent.h"
#include "es_orchestrator.h"
#include "es_memory.h"
#include "llama.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <signal.h>

// ---- ANSI color helpers ----
#define ANSI_RESET    "\033[0m"
#define ANSI_BOLD     "\033[1m"
#define ANSI_DIM      "\033[2m"
#define ANSI_RED      "\033[31m"
#define ANSI_GREEN    "\033[32m"
#define ANSI_YELLOW   "\033[33m"
#define ANSI_BLUE     "\033[34m"
#define ANSI_MAGENTA  "\033[35m"
#define ANSI_CYAN     "\033[36m"
#define ANSI_GRAY     "\033[90m"

#define ES_PROMPT_COLOR  ANSI_BOLD ANSI_CYAN
#define ES_OUTPUT_COLOR  ANSI_RESET
#define ES_SYSTEM_COLOR  ANSI_GRAY
#define ES_ERROR_COLOR   ANSI_RED
#define ES_AGENT_COLOR   ANSI_YELLOW

// ---- CLI defaults ----
#define DEFAULT_CTX_SIZE      4096
#define DEFAULT_BATCH_SIZE    512
#define DEFAULT_N_THREADS     4
#define DEFAULT_MAX_TOKENS    512
#define DEFAULT_TEMPERATURE   0.7f
#define DEFAULT_TOP_P         0.95f
#define MAX_TURNS             64      // max conversation turns
#define MAX_MSG_LEN           8192    // max chars per message

// ---- Multi-turn conversation state ----
typedef struct {
    char   role[16];
    char  *content;
} es_turn_t;

typedef struct {
    es_turn_t turns[MAX_TURNS * 2];  // user+assistant per turn
    int       n;
} es_conv_t;

static es_conv_t conv = {0};

static bool conv_add(const char *role, const char *content) {
    if (conv.n >= MAX_TURNS * 2) return false;
    snprintf(conv.turns[conv.n].role, sizeof(conv.turns[conv.n].role), "%s", role);
    conv.turns[conv.n].content = strdup(content);
    conv.n++;
    return true;
}

static void conv_reset(void) {
    for (int i = 0; i < conv.n; i++) free(conv.turns[i].content);
    conv.n = 0;
}

// ---- Interrupt flag (Ctrl-C stops generation, not the process) ----
// The engine's cancel flag is the source of truth; this flag drives the REPL loop.
static volatile bool g_interrupted = false;
static es_engine_t  *g_engine_for_signal = NULL;
static void sig_handler(int sig) {
    (void)sig;
    g_interrupted = true;
    if (g_engine_for_signal) es_engine_cancel(g_engine_for_signal);
}

// ---- Help text ----
static void print_usage(const char *prog) {
    fprintf(stderr,
        ANSI_BOLD "Embershard" ANSI_RESET " — local LLM control plane\n\n"
        "Usage: %s -m <model.gguf> [options]\n\n"
        "Options:\n"
        "  -m <path>      Model file (required)\n"
        "  -p <prompt>    Single-shot prompt (disables interactive REPL)\n"
        "  -c <n>         Context size (default: %d)\n"
        "  -t <n>         CPU threads (default: %d)\n"
        "  -n <n>         Max tokens per turn (default: %d)\n"
        "  --temp <f>     Sampling temperature (default: %.1f; 0=greedy)\n"
        "  --top-p <f>    Top-P sampling (default: %.2f)\n"
        "  --agent        Enable multi-agent mode (planner→executor→critic)\n"
        "  --verbose      Verbose agent pipeline output\n\n"
        "Interactive commands:\n"
        "  /reset         Clear conversation and KV cache\n"
        "  /status        KV cache usage and memory stats\n"
        "  /bench         Show last benchmark results\n"
        "  /agent         Toggle agent mode on/off\n"
        "  /help          Show this help\n"
        "  /quit          Exit\n\n",
        prog, DEFAULT_CTX_SIZE, DEFAULT_N_THREADS, DEFAULT_MAX_TOKENS,
        (double)DEFAULT_TEMPERATURE, (double)DEFAULT_TOP_P);
}

// ---- Single-shot mode (equivalent to Phase 1 main) ----
static int run_single_shot(es_engine_t *engine, const char *prompt,
                            int32_t max_tokens, float temperature, float top_p) {
    printf(ES_SYSTEM_COLOR "[embershard] single-shot mode" ANSI_RESET "\n");
    printf(ES_SYSTEM_COLOR "[prompt] " ANSI_RESET "%s\n\n", prompt);

    es_bench_t bench;
    es_bench_start(&bench);

    if (!es_engine_ingest(engine, prompt)) {
        fprintf(stderr, ES_ERROR_COLOR "[error] prompt ingestion failed\n" ANSI_RESET);
        return 1;
    }
    es_bench_prompt_done(&bench, es_engine_get_pos(engine));

    struct llama_sampler *sampler = es_engine_make_sampler(temperature, top_p);

    printf(ES_OUTPUT_COLOR);
    fflush(stdout);

    for (int32_t i = 0; i < max_tokens && !g_interrupted; i++) {
        llama_token tok = es_engine_step_seq(engine, sampler, 0, &engine->pos);
        if (tok < 0 || es_engine_is_eos(engine, tok)) break;

        if (i == 0) es_bench_first_token(&bench);

        const char *piece = es_engine_token_to_str(engine, tok);
        if (piece) { printf("%s", piece); fflush(stdout); }
    }
    printf(ANSI_RESET "\n");

    es_engine_free_sampler(sampler);

    es_bench_end(&bench, es_engine_get_pos(engine) - bench.prompt_tokens);
    es_bench_result_t r = es_bench_report(&bench);
    es_bench_print(&r);
    printf(ES_SYSTEM_COLOR "[ctx] %d / %d tokens\n" ANSI_RESET,
           es_engine_ctx_used(engine), es_engine_ctx_max(engine));
    return 0;
}

// ---- Streaming callback for REPL generation ----
typedef struct { es_bench_t *bench; bool first; } repl_cb_state_t;

static void repl_token_cb(const char *piece, void *ud) {
    repl_cb_state_t *s = (repl_cb_state_t *)ud;
    if (s->first) { es_bench_first_token(s->bench); s->first = false; }
    printf("%s", piece);
    fflush(stdout);
}

// ---- Multi-turn REPL chat loop ----
static int run_repl(es_engine_t *engine, int32_t max_tokens,
                    float temperature, float top_p,
                    bool agent_mode, bool verbose) {
    printf(ES_SYSTEM_COLOR
           "╔════════════════════════════════════╗\n"
           "║  Embershard  —  local LLM engine   ║\n"
           "╚════════════════════════════════════╝\n"
           ANSI_RESET);
    printf(ES_SYSTEM_COLOR
           "model ctx: %d tokens | temp: %.2f | agent: %s\n"
           "type /help for commands, Ctrl-C interrupts generation\n\n"
           ANSI_RESET,
           es_engine_ctx_max(engine), (double)temperature,
           agent_mode ? "ON" : "OFF");

    // Orchestrator for agent mode
    es_orchestrator_t *orch = NULL;
    if (agent_mode) {
        orch = es_orchestrator_create(engine, verbose);
        if (!orch) {
            fprintf(stderr, ES_ERROR_COLOR "[error] orchestrator init failed\n" ANSI_RESET);
            agent_mode = false;
        }
    }

    // Per-turn sampler (used in non-agent mode)
    struct llama_sampler *sampler = es_engine_make_sampler(temperature, top_p);

    // Chat template buffers for multi-turn
    char *formatted     = malloc(131072); // 128 KB for full conversation
    char *prev_formatted = malloc(131072);
    char  input_buf[MAX_MSG_LEN];
    char  resp_buf[32768];
    if (!formatted || !prev_formatted) {
        fprintf(stderr, ES_ERROR_COLOR "[error] OOM\n" ANSI_RESET);
        es_engine_free_sampler(sampler);
        if (orch) es_orchestrator_free(orch);
        free(formatted); free(prev_formatted);
        return 1;
    }
    int32_t prev_fmt_len = 0;
    bool    first_turn   = true;

    while (true) {
        // ── Prompt ─────────────────────────────────────────────────────────
        printf(ES_PROMPT_COLOR "you" ANSI_RESET ANSI_DIM " › " ANSI_RESET);
        fflush(stdout);

        if (!fgets(input_buf, sizeof(input_buf), stdin)) break;

        // Strip trailing newline
        int32_t ilen = (int32_t)strlen(input_buf);
        while (ilen > 0 && (input_buf[ilen-1] == '\n' || input_buf[ilen-1] == '\r')) {
            input_buf[--ilen] = '\0';
        }
        if (ilen == 0) continue;

        // ── Commands ───────────────────────────────────────────────────────
        if (strcmp(input_buf, "/quit") == 0 || strcmp(input_buf, "/exit") == 0) break;

        if (strcmp(input_buf, "/help") == 0) {
            printf(ES_SYSTEM_COLOR
                   "Commands: /reset /status /bench /agent /quit\n"
                   ANSI_RESET);
            continue;
        }

        if (strcmp(input_buf, "/reset") == 0) {
            es_engine_reset(engine);
            conv_reset();
            prev_fmt_len = 0;
            first_turn   = true;
            printf(ES_SYSTEM_COLOR "[reset] context cleared\n" ANSI_RESET);
            if (orch) {
                es_orchestrator_free(orch);
                orch = es_orchestrator_create(engine, verbose);
            }
            continue;
        }

        if (strcmp(input_buf, "/status") == 0) {
            printf(ES_SYSTEM_COLOR
                   "[ctx] %d / %d tokens (%.0f%%)\n"
                   ANSI_RESET,
                   es_engine_ctx_used(engine), es_engine_ctx_max(engine),
                   (double)es_engine_ctx_used(engine) /
                   (double)es_engine_ctx_max(engine) * 100.0);
            es_memory_print_stats();
            continue;
        }

        if (strcmp(input_buf, "/bench") == 0) {
            printf(ES_SYSTEM_COLOR "[bench] run a query first\n" ANSI_RESET);
            continue;
        }

        if (strcmp(input_buf, "/agent") == 0) {
            agent_mode = !agent_mode;
            if (agent_mode && !orch) {
                orch = es_orchestrator_create(engine, verbose);
                if (!orch) { agent_mode = false; }
            }
            printf(ES_SYSTEM_COLOR "[agent] mode %s\n" ANSI_RESET,
                   agent_mode ? "ON" : "OFF");
            continue;
        }

        g_interrupted = false;
        es_engine_uncancel(engine);

        // ── Agent mode pipeline ─────────────────────────────────────────────
        if (agent_mode && orch) {
            printf(ES_AGENT_COLOR
                   "⟳ planner" ANSI_RESET " › " ES_AGENT_COLOR
                   "executor" ANSI_RESET " › " ES_AGENT_COLOR
                   "critic\n" ANSI_RESET);

            printf(ES_OUTPUT_COLOR "embershard › " ANSI_RESET);
            fflush(stdout);

            es_bench_t bench;
            es_bench_start(&bench);

            // stream_cb prints critic output token by token
            int32_t n = es_orchestrator_run(orch, input_buf, max_tokens,
                                             resp_buf, sizeof(resp_buf),
                                             repl_token_cb,
                                             &(repl_cb_state_t){&bench, true});
            printf("\n");

            if (n < 0) {
                printf(ES_ERROR_COLOR "[error] orchestrator failed\n" ANSI_RESET);
            } else {
                es_bench_end(&bench, n);
                es_bench_result_t r = es_bench_report(&bench);
                printf(ES_SYSTEM_COLOR
                       "[bench] gen=%.0f t/s | mem=%.0f MB\n"
                       ANSI_RESET,
                       r.gen_tokens > 0
                           ? (double)r.gen_tokens * 1000.0 / (double)(r.gen_ms + 1)
                           : 0.0,
                       (double)r.mem_used_bytes / 1e6);
            }
            continue;
        }

        // ── Multi-turn chat mode ────────────────────────────────────────────
        // Add user turn to conversation history
        conv_add("user", input_buf);

        // Build llama_chat_message array from conversation history
        struct llama_chat_message *msgs = malloc(sizeof(struct llama_chat_message)
                                                 * (size_t)conv.n);
        if (!msgs) continue;
        for (int i = 0; i < conv.n; i++) {
            msgs[i].role    = conv.turns[i].role;
            msgs[i].content = conv.turns[i].content;
        }

        // Apply chat template to full conversation (with assistant prefix)
        int32_t fmt_len = es_engine_apply_chat_template(engine, msgs, conv.n,
                                                          true, formatted, 131072);
        free(msgs);

        if (fmt_len <= 0) {
            // Fallback: just ingest user input directly
            fmt_len = snprintf(formatted, 131072, "\nUser: %s\nAssistant:", input_buf);
        }

        // Ingest only the new suffix (tokens added since last turn)
        const char *new_suffix    = formatted + prev_fmt_len;
        int32_t    new_suffix_len = fmt_len - prev_fmt_len;
        (void)new_suffix_len;

        es_bench_t bench;
        es_bench_start(&bench);

        // add_special=true only on the first turn (to get BOS token)
        int32_t n_ing = es_engine_ingest_seq(engine, new_suffix,
                                              0, engine->pos, first_turn);
        if (n_ing < 0) {
            printf(ES_ERROR_COLOR "[error] ingestion failed\n" ANSI_RESET);
            conv.n--;
            free(conv.turns[conv.n].content);
            continue;
        }
        engine->pos += n_ing;
        first_turn   = false;

        es_bench_prompt_done(&bench, n_ing);

        // Context pressure check: auto-compress at 85% usage.
        // Evict oldest KV tokens via sliding-window — does NOT touch conversation history.
        if ((float)engine->pos / (float)engine->n_ctx_max > 0.85f) {
            int32_t old_pos = engine->pos;
            if (es_engine_kv_can_shift(engine)) {
                int32_t n_evict = engine->pos / 2; // evict oldest 50%
                es_engine_kv_seq_rm(engine, 0, 0, n_evict);
                es_engine_kv_seq_add(engine, 0, n_evict, -1, -n_evict);
                engine->pos -= n_evict;
                // prev_fmt_len must be rewound too so ingest picks up from the right place
                if (prev_fmt_len > engine->pos) prev_fmt_len = 0;
                printf(ES_SYSTEM_COLOR
                       "[mem] ctx compressed %d→%d tokens (history preserved)\n" ANSI_RESET,
                       old_pos, engine->pos);
            } else {
                // Backend doesn't support shifting: hard reset (last resort)
                es_engine_reset(engine);
                engine->pos = 0;
                prev_fmt_len = 0;
                printf(ES_SYSTEM_COLOR "[mem] ctx full — reset (backend has no shift)\n" ANSI_RESET);
            }
        }

        // Generate response
        printf(ES_OUTPUT_COLOR "embershard › " ANSI_RESET);
        fflush(stdout);

        char resp_accum[32768];
        int32_t resp_len = 0;
        bool    gen_first = true;

        for (int32_t i = 0; i < max_tokens && !g_interrupted; i++) {
            llama_token tok = es_engine_step_seq(engine, sampler, 0, &engine->pos);
            if (tok < 0 || es_engine_is_eos(engine, tok)) break;

            if (gen_first) { es_bench_first_token(&bench); gen_first = false; }

            const char *piece = es_engine_token_to_str(engine, tok);
            if (!piece) break;

            printf("%s", piece);
            fflush(stdout);

            int32_t plen = (int32_t)strlen(piece);
            if (resp_len + plen < (int32_t)sizeof(resp_accum) - 1) {
                memcpy(resp_accum + resp_len, piece, (size_t)plen);
                resp_len += plen;
            }
        }
        resp_accum[resp_len] = '\0';
        printf("\n");

        // Add assistant response to conversation history
        conv_add("assistant", resp_accum);

        // Update prev_formatted: re-apply template with assistant response
        {
            struct llama_chat_message *all_msgs = malloc(
                sizeof(struct llama_chat_message) * (size_t)conv.n);
            if (all_msgs) {
                for (int i = 0; i < conv.n; i++) {
                    all_msgs[i].role    = conv.turns[i].role;
                    all_msgs[i].content = conv.turns[i].content;
                }
                // add_ass=false: full template including completed assistant turn
                int32_t new_len = es_engine_apply_chat_template(
                    engine, all_msgs, conv.n, false, prev_formatted, 131072);
                if (new_len > 0) prev_fmt_len = new_len;
                free(all_msgs);
            }
        }

        es_bench_end(&bench, es_engine_get_pos(engine) - bench.prompt_tokens);
        es_bench_result_t r = es_bench_report(&bench);
        printf(ES_SYSTEM_COLOR
               "[bench] prompt=%d t, %.0f t/s | gen=%d t, %.0f t/s | ttft=%.0f ms\n"
               ANSI_RESET,
               r.prompt_tokens,
               r.prompt_ms > 0 ? (double)r.prompt_tokens * 1000.0 / (double)r.prompt_ms : 0.0,
               r.gen_tokens,
               r.gen_ms > 0 ? (double)r.gen_tokens * 1000.0 / (double)r.gen_ms : 0.0,
               (double)r.first_token_ms);
    }

    // Cleanup
    es_engine_free_sampler(sampler);
    if (orch) es_orchestrator_free(orch);
    conv_reset();
    free(formatted);
    free(prev_formatted);
    return 0;
}

// ---- Entry point ----

int main(int argc, char **argv) {
    signal(SIGINT, sig_handler);

    const char *model_path  = NULL;
    const char *prompt      = NULL;
    int32_t     ctx_size    = DEFAULT_CTX_SIZE;
    int32_t     n_threads   = DEFAULT_N_THREADS;
    int32_t     max_tokens  = DEFAULT_MAX_TOKENS;
    float       temperature = DEFAULT_TEMPERATURE;
    float       top_p       = DEFAULT_TOP_P;
    bool        agent_mode  = false;
    bool        verbose     = false;

    for (int i = 1; i < argc; i++) {
        if      (strcmp(argv[i], "-m") == 0     && i+1 < argc) model_path  = argv[++i];
        else if (strcmp(argv[i], "-p") == 0     && i+1 < argc) prompt      = argv[++i];
        else if (strcmp(argv[i], "-c") == 0     && i+1 < argc) ctx_size    = atoi(argv[++i]);
        else if (strcmp(argv[i], "-t") == 0     && i+1 < argc) n_threads   = atoi(argv[++i]);
        else if (strcmp(argv[i], "-n") == 0     && i+1 < argc) max_tokens  = atoi(argv[++i]);
        else if (strcmp(argv[i], "--temp") == 0 && i+1 < argc) temperature = (float)atof(argv[++i]);
        else if (strcmp(argv[i], "--top-p") == 0 && i+1 < argc) top_p      = (float)atof(argv[++i]);
        else if (strcmp(argv[i], "--agent") == 0)               agent_mode  = true;
        else if (strcmp(argv[i], "--verbose") == 0)             verbose     = true;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        }
    }

    if (!model_path) {
        print_usage(argv[0]);
        return 1;
    }

    printf(ES_SYSTEM_COLOR "[embershard] loading %s ...\n" ANSI_RESET, model_path);

    es_engine_config_t config = {
        .model_path   = model_path,
        .n_gpu_layers = -1,
        .n_ctx        = ctx_size,
        .n_batch      = DEFAULT_BATCH_SIZE,
        .n_threads    = n_threads,
        .use_mmap     = true,
        .flash_attn   = true,
    };

    es_engine_t *engine = es_engine_init(config);
    if (!engine) {
        fprintf(stderr, ES_ERROR_COLOR "[error] engine init failed\n" ANSI_RESET);
        return 1;
    }
    g_engine_for_signal = engine;

    printf(ES_SYSTEM_COLOR "[embershard] ready  ctx=%d  threads=%d  gpu=all\n"
           ANSI_RESET, ctx_size, n_threads);
    es_memory_print_stats();
    printf("\n");

    int ret;
    if (prompt) {
        // Single-shot mode
        ret = run_single_shot(engine, prompt, max_tokens, temperature, top_p);
    } else {
        // Interactive REPL
        ret = run_repl(engine, max_tokens, temperature, top_p, agent_mode, verbose);
    }

    es_engine_free(engine);
    return ret;
}
