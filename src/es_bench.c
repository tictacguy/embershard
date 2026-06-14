#include "es_bench.h"
#include <stdio.h>
#include <mach/mach_time.h>
#include <mach/mach.h>

static double ns_per_tick = 0.0;

static void ensure_timebase(void) {
    if (ns_per_tick == 0.0) {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        ns_per_tick = (double)info.numer / (double)info.denom;
    }
}

static double ticks_to_ms(uint64_t ticks) {
    return (double)ticks * ns_per_tick / 1e6;
}

void es_bench_start(es_bench_t *b) {
    ensure_timebase();
    *b = (es_bench_t){0};
    b->t_start = mach_absolute_time();
}

void es_bench_prompt_done(es_bench_t *b, int32_t n_tokens) {
    b->t_prompt_done = mach_absolute_time();
    b->prompt_tokens = n_tokens;
}

void es_bench_first_token(es_bench_t *b) {
    b->t_first_token = mach_absolute_time();
}

void es_bench_end(es_bench_t *b, int32_t gen_tokens) {
    b->t_end = mach_absolute_time();
    b->gen_tokens = gen_tokens;
}

es_bench_result_t es_bench_report(es_bench_t *b) {
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    size_t mem = 0;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        mem = info.resident_size;
    }

    return (es_bench_result_t){
        .prompt_ms = ticks_to_ms(b->t_prompt_done - b->t_start),
        .gen_ms = ticks_to_ms(b->t_end - b->t_prompt_done),
        .prompt_tokens = b->prompt_tokens,
        .gen_tokens = b->gen_tokens,
        .first_token_ms = ticks_to_ms(b->t_first_token - b->t_start),
        .mem_used_bytes = mem,
    };
}

void es_bench_print(es_bench_result_t *r) {
    printf("\n=== embershard bench ===\n");
    printf("prompt:  %d tokens in %.1f ms (%.1f t/s)\n",
           r->prompt_tokens, r->prompt_ms,
           r->prompt_tokens > 0 ? r->prompt_tokens / (r->prompt_ms / 1000.0) : 0);
    printf("gen:     %d tokens in %.1f ms (%.1f t/s)\n",
           r->gen_tokens, r->gen_ms,
           r->gen_tokens > 0 ? r->gen_tokens / (r->gen_ms / 1000.0) : 0);
    printf("ttft:    %.1f ms\n", r->first_token_ms);
    printf("memory:  %.1f MB (resident)\n", r->mem_used_bytes / (1024.0 * 1024.0));
    printf("========================\n");
}
