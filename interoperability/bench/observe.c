/* Common benchmark observation only: no codec, crypto or application semantics. */
#include <stddef.h>
#include <stdint.h>
#include <sys/resource.h>
/* Keep complete operation results visible across a non-LTO ABI boundary without reading/writing their bytes. */
void rb_observe(const void *data, size_t size) {
    __asm__ volatile("" : : "r"(data), "r"(size) : "memory");
}
/* Normalize the OS process high-water RSS to bytes; include setup/runtime memory, not just codec allocations. */
uint64_t rb_peak_rss(void) {
    struct rusage usage;
    /* OS observation failure has no valid memory measurement. */
    if (getrusage(RUSAGE_SELF, &usage)) return 0;
#ifdef __APPLE__
    return (uint64_t)usage.ru_maxrss;
#else
    return (uint64_t)usage.ru_maxrss * 1024;
#endif
}
/* Use OS nanosecond monotonic resolution when an SDK's nominal ns clock quantizes to microseconds. */
#include <time.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif
uint64_t rb_now_ns(void) {
#ifdef __APPLE__
    mach_timebase_info_data_t scale;
    /* macOS CLOCK_MONOTONIC can quantize short calls; mach absolute time retains hardware resolution. */
    if (mach_timebase_info(&scale) != KERN_SUCCESS || !scale.denom) return 0;
    uint64_t ticks = mach_absolute_time();
    return (ticks / scale.denom) * scale.numer + (ticks % scale.denom) * scale.numer / scale.denom;
#else
    struct timespec value;
    /* A failed OS clock cannot be accepted as a fabricated positive timing sample. */
    if (clock_gettime(CLOCK_MONOTONIC, &value)) return 0;
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
#endif
}
