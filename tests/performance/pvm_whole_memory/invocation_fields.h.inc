/* Copyright (c) 2026 Ragnarök contributors */
/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Private owned ABI fragment; the projector removes exactly these three comment lines. */
    void *writer;
    uint64_t read_tag; void *read_pointer;
    uint64_t write_tag; void *write_pointer;
    void *epoch_pointer;
    uint64_t read_epoch, write_epoch, fast_loads, fast_stores, slow_loads, slow_stores;
    void *test_probe;