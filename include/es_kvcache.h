#ifndef ES_KVCACHE_H
#define ES_KVCACHE_H

#include "es_engine.h"
#include <stdint.h>
#include <stdbool.h>

// --- Embershard KV Cache Manager ---
// Tracks which sequence IDs are in use so agents each get an isolated KV slot
// while sharing the same model weights.

#define ES_KV_MAX_SEQS 16

typedef struct {
    es_engine_t *engine;
    bool         seq_used[ES_KV_MAX_SEQS]; // seq 0 is owned by the engine
} es_kvcache_t;

// Lifecycle
es_kvcache_t *es_kvcache_create(es_engine_t *engine);
void          es_kvcache_free(es_kvcache_t *kvc);

// Sequence allocation.
// Returns allocated seq_id (>= 1), or -1 if the pool is exhausted.
llama_seq_id es_kvcache_alloc_seq(es_kvcache_t *kvc);
// Release sequence: removes its KV entries and returns the slot.
void         es_kvcache_free_seq(es_kvcache_t *kvc, llama_seq_id seq_id);

#endif // ES_KVCACHE_H
