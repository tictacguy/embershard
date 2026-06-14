#include "es_memory.h"
#include <stdio.h>

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/vm_statistics.h>
#include <sys/types.h>
#include <sys/sysctl.h>

static uint64_t get_total_ram(void) {
    uint64_t ram = 0;
    size_t len = sizeof(ram);
    sysctlbyname("hw.memsize", &ram, &len, NULL, 0);
    return ram;
}

static uint64_t get_available_ram(void) {
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                           (host_info64_t)&vm_stats, &count) != KERN_SUCCESS) {
        return 0;
    }
    vm_size_t page_size;
    host_page_size(mach_host_self(), &page_size);
    return (uint64_t)(vm_stats.free_count + vm_stats.inactive_count) * page_size;
}

es_mem_stats_t es_memory_get_stats(void) {
    es_mem_stats_t stats = {0};

    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                   (task_info_t)&info, &count) == KERN_SUCCESS) {
        stats.resident_bytes = info.resident_size;
        stats.virtual_bytes  = info.virtual_size;
    }

    uint64_t total_ram = get_total_ram();
    uint64_t avail     = get_available_ram();
    stats.available_bytes = avail;

    if (total_ram > 0) {
        uint64_t used = total_ram > avail ? total_ram - avail : 0;
        stats.pressure = (float)used / (float)total_ram;
    }

    return stats;
}

void es_memory_print_stats(void) {
    es_mem_stats_t s = es_memory_get_stats();
    fprintf(stderr,
            "[mem] RSS=%.1f MB  VSZ=%.1f MB  avail=%.1f MB  pressure=%.1f%%\n",
            (double)s.resident_bytes / 1e6,
            (double)s.virtual_bytes  / 1e6,
            (double)s.available_bytes / 1e6,
            (double)s.pressure * 100.0);
}
