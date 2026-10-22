// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

/* Measure identical one-shot C ABI calls and dependent Merkle kernels, with no provider-specific loop. */
#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Both adapters borrow input synchronously and publish a complete 32-byte digest on success. */
typedef int (*hashfn)(const uint8_t *, size_t, uint8_t *);

/* Monotonic nanoseconds bracket only workload execution, excluding startup and allocation. */
static uint64_t now(void) {
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time)) exit(8);
    return (uint64_t)time.tv_sec * 1000000000ULL + time.tv_nsec;
}

/* Backend failure stops the run before partial output can become a successful measurement. */
static void checked(hashfn hash, const uint8_t *input, size_t size, uint8_t *output) {
    if (hash(input, size, output) != 1) {
        fprintf(stderr, "provider failed\n");
        exit(3);
    }
}

/* Decode an exact little-endian fixture length without host-endian assumptions. */
static uint32_t read_u32(FILE *file) {
    uint8_t bytes[4];
    if (fread(bytes, 1, 4, file) != 4) exit(6);
    return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
        (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}

/* Compare every provider digest with Python hashlib's independently generated exact bytes. */
static void verify(hashfn hash, const char *path, size_t expected) {
    FILE *file = fopen(path, "rb");
    uint8_t magic[4], data[65536], wanted[32], output[32];
    if (!file || fread(magic, 1, 4, file) != 4 || memcmp(magic, "B2B1", 4)) exit(6);
    size_t count = read_u32(file);
    if (count != expected || count > 10000) exit(6);
    for (size_t i = 0; i < count; i++) {
        /* Bound each input before reading into fixed caller-owned scratch storage. */
        size_t size = read_u32(file);
        if (size > sizeof(data) || fread(data, 1, size, file) != size ||
            fread(wanted, 1, 32, file) != 32) exit(6);
        checked(hash, data, size, output);
        if (memcmp(output, wanted, 32)) {
            fprintf(stderr, "digest mismatch at vector %zu\n", i);
            exit(7);
        }
    }
    if (fgetc(file) != EOF || ferror(file)) exit(6);
    fclose(file);
    printf("verified %zu\n", count);
}

/* Reject malformed or unbounded command arguments before allocating or starting the timer. */
static size_t number(const char *value, size_t maximum) {
    char *end;
    errno = 0;
    unsigned long long parsed = strtoull(value, &end, 10);
    if (!*value || *value == '-' || *end || errno || parsed > maximum) exit(2);
    return (size_t)parsed;
}

/* Load one selected provider; the caller compares independently validated equal-work invocations. */
int main(int argc, char **argv) {
    if (argc != 6) return 2;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "%s\n", dlerror());
        return 3;
    }
    hashfn hash = (hashfn)dlsym(handle, argv[2]);
    if (!hash) {
        fprintf(stderr, "%s\n", dlerror());
        return 4;
    }
    if (!strcmp(argv[3], "verify")) {
        /* Correctness mode is a separate process and never enters a timing interval. */
        verify(hash, argv[4], number(argv[5], 10000));
        dlclose(handle);
        return 0;
    }
    int tree = !strcmp(argv[3], "tree");
    if (!tree && strcmp(argv[3], "hash")) return 2;
    size_t size = number(argv[4], 65536), iterations = number(argv[5], 1000000);
    if (!iterations || (tree && size != 64)) return 2;
    const size_t leaves = 4096, corpus = 1024;
    size_t stride = size ? size : 1;
    size_t bytes = tree ? leaves * 64 : stride * corpus;
    uint8_t *input = malloc(bytes), *nodes = malloc(2 * leaves * 32);
    uint8_t output[32] = {0}, wire[64];
    if (!input || !nodes) return 5;
    for (size_t i = 0; i < bytes; i++) {
        /* Rotating messages prevent a single repeated input from being the entire workload. */
        input[i] = (uint8_t)(i * 131 + i / stride * 17 + size * 3);
    }
    if (tree) {
        /* Every leaf contains the canonical inline-32-byte header and raw key/value fields. */
        for (size_t i = 0; i < leaves; i++) input[i * 64] = 0xa0;
    }
    for (size_t i = 0; i < 64; i++) checked(hash, input, tree ? 64 : size, output);
    uint64_t checksum = 0, start = now();
    for (size_t iteration = 0; iteration < iterations; iteration++) {
        if (tree) {
            /* Parents consume completed child digests; allocation and leaf setup are already complete. */
            for (size_t i = 0; i < leaves; i++) {
                checked(hash, input + i * 64, 64, nodes + (leaves + i) * 32);
            }
            for (size_t i = leaves - 1; i > 0; i--) {
                memcpy(wire, nodes + 2 * i * 32, 64);
                wire[0] &= 127;
                checked(hash, wire, 64, nodes + i * 32);
            }
            checksum += nodes[32 + (iteration & 31)];
        } else {
            /* One checksum byte per completed hash is validated independently after timing. */
            checked(hash, input + (iteration & (corpus - 1)) * stride, size, output);
            checksum += output[iteration & 31];
        }
    }
    uint64_t elapsed = now() - start;
    const uint8_t *last = tree ? nodes + 32 : output;
    printf("%llu %llu ", (unsigned long long)elapsed, (unsigned long long)checksum);
    for (int i = 0; i < 32; i++) printf("%02x", last[i]);
    puts("");
    free(nodes);
    free(input);
    dlclose(handle);
    return 0;
}
