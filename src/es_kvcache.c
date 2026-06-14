#include "es_kvcache.h"
#include <stdlib.h>
#include <stdio.h>

es_kvcache_t *es_kvcache_create(es_engine_t *engine) {
    if (!engine) return NULL;
    es_kvcache_t *kvc = calloc(1, sizeof(es_kvcache_t));
    if (!kvc) return NULL;
    kvc->engine = engine;
    kvc->seq_used[0] = true; // seq 0 is owned by the engine
    return kvc;
}

void es_kvcache_free(es_kvcache_t *kvc) {
    if (!kvc) return;
    for (int i = 1; i < ES_KV_MAX_SEQS; i++) {
        if (kvc->seq_used[i]) {
            es_engine_kv_seq_rm(kvc->engine, (llama_seq_id)i, 0, -1);
        }
    }
    free(kvc);
}

llama_seq_id es_kvcache_alloc_seq(es_kvcache_t *kvc) {
    if (!kvc) return -1;
    for (int i = 1; i < ES_KV_MAX_SEQS; i++) {
        if (!kvc->seq_used[i]) {
            kvc->seq_used[i] = true;
            return (llama_seq_id)i;
        }
    }
    fprintf(stderr, "[es_kvcache] seq pool exhausted (max %d)\n", ES_KV_MAX_SEQS);
    return -1;
}

void es_kvcache_free_seq(es_kvcache_t *kvc, llama_seq_id seq_id) {
    if (!kvc || seq_id <= 0 || seq_id >= ES_KV_MAX_SEQS) return;
    if (!kvc->seq_used[(int)seq_id]) return;
    es_engine_kv_seq_rm(kvc->engine, seq_id, 0, -1);
    kvc->seq_used[(int)seq_id] = false;
}
