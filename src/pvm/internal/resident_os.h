/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private data-only anonymous mapping and exact release.
 */
#ifndef PVM_RESIDENT_OS_H
#define PVM_RESIDENT_OS_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

/* These private status values are independent of errno: 0 success, 1 size, 2 refusal. */
typedef struct {
    void *data;
    size_t logical, backing;
    int status;
} pvm_resident_allocation;

static pvm_resident_allocation pvm_resident_refused(int status) {
    /* Failed records never contain allocation authority. */
    pvm_resident_allocation result = {NULL, 0, 0, status};
    return result;
}

static pvm_resident_allocation pvm_resident_map(size_t logical) {
    /* Empty success performs no syscall and owns no backing span. */
    if (logical == 0) return pvm_resident_refused(0);
    /* Guest4096-byte pages do not prescribe the host mapping granularity. */
    long queried = sysconf(_SC_PAGESIZE);
    if (queried <= 0) return pvm_resident_refused(2);
    size_t page = (size_t)queried;
    size_t remainder = logical % page;
    size_t extra = remainder ? page - remainder : 0;
    /* Check the full host rounding before addition or any OS request. */
    if (logical > SIZE_MAX - extra) return pvm_resident_refused(1);
    size_t backing = logical + extra;
    void *data = mmap(NULL, backing, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    /* A failed mapping never enters a Nim owning alternative. */
    if (data == MAP_FAILED) return pvm_resident_refused(2);
    if (data == NULL) {
        /* Nil is reserved for an empty owner; retire an unusual address-zero success. */
        if (munmap(data, backing) != 0) abort();
        return pvm_resident_refused(2);
    }
    pvm_resident_allocation result = {data, logical, backing, 0};
    return result;
}

static void pvm_resident_unmap(void *data, size_t backing) {
    /* Default/moved owners have no authority; positive owners release the exact original span. */
    if (data == NULL) return;
    /* Failed release is fatal; it cannot silently retire owner-held accounting. */
    if (backing == 0 || munmap(data, backing) != 0) abort();
}

#endif
