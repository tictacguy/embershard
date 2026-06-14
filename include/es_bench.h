#ifndef ES_BENCH_H
#define ES_BENCH_H

#include <stdint.h>
#include <stddef.h>

// --- Embershard Benchmark ---
// Integrated latency and throughput measurement.

typedef struct {
    double   prompt_ms;       // total prompt processing time
    double   gen_ms;          // total generation time
    int32_t  prompt_tokens;   // tokens in the prompt
    int32_t  gen_tokens;      // tokens generated
    double   first_token_ms;  // time to first token
    size_t   mem_used_bytes;  // estimated memory in use
} es_bench_result_t;

typedef struct {
    uint64_t t_start;
    uint64_t t_prompt_done;
    uint64_t t_first_token;
    uint64_t t_end;
    int32_t  prompt_tokens;
    int32_t  gen_tokens;
} es_bench_t;

void es_bench_start(es_bench_t *b);
void es_bench_prompt_done(es_bench_t *b, int32_t n_tokens);
void es_bench_first_token(es_bench_t *b);
void es_bench_end(es_bench_t *b, int32_t gen_tokens);
es_bench_result_t es_bench_report(es_bench_t *b);
void es_bench_print(es_bench_result_t *r);

#endif // ES_BENCH_H
