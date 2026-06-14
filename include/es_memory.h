#ifndef ES_MEMORY_H
#define ES_MEMORY_H

#include <stdint.h>

// --- Embershard Memory Monitor ---
// Reads process RSS and system memory pressure via mach_task_info / vm_statistics64.

typedef struct {
    uint64_t resident_bytes;   // process RSS
    uint64_t virtual_bytes;    // process VSZ
    uint64_t available_bytes;  // system free + inactive RAM
    float    pressure;         // 0.0 (idle) → 1.0 (critical)
} es_mem_stats_t;

es_mem_stats_t es_memory_get_stats(void);
void           es_memory_print_stats(void);

#endif // ES_MEMORY_H
