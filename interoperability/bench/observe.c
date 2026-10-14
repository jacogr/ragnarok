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
