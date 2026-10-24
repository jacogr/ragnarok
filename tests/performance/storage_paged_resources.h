/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

/* Test-only SDK descriptor observations exclude their own directory handle. */
#ifndef RAGNAROK_PAGED_RESOURCES_H
#define RAGNAROK_PAGED_RESOURCES_H
#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <limits.h>
#include <sys/resource.h>

static inline int ragnarok_paged_descriptors(void) {
    /* A bounded scan observes resources; it never grants authority over database names. */
#ifdef __linux__
    DIR *directory = opendir("/proc/self/fd");
#else
    DIR *directory = opendir("/dev/fd");
#endif
    if (directory == NULL) return -1;
    int count = 0;
    int failed = 0;
    for (;;) {
        /* Preserve readdir failure independently of successful descriptor retirement. */
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (entry == NULL) {
            failed = errno != 0;
            break;
        }
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) ++count;
        if (count > 1024) {
            failed = 1;
            break;
        }
    }
    if (closedir(directory) != 0 || failed || count == 0) return -1;
    return count - 1;
}
/* Observe storage-work peak RSS and faults with actual SDK layout and platform units. */
static inline long long ragnarok_paged_usage(int selector) {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) return -1;
    if (selector == 1) return usage.ru_minflt;
    if (selector == 2) return usage.ru_majflt;
    if (selector != 0 || usage.ru_maxrss < 0) return -1;
#ifdef __linux__
    /* Linux supplies KiB; prove conversion before multiplying. */
    if ((unsigned long long)usage.ru_maxrss > (unsigned long long)LLONG_MAX / 1024) return -1;
    return (long long)usage.ru_maxrss * 1024;
#else
    /* The other admitted profile is Darwin, whose SDK reports bytes. */
    return usage.ru_maxrss;
#endif
}
#endif
