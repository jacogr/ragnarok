/* Copyright (c) 2026 Ragnarök contributors */
/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Private owned ABI fragment; the projector removes exactly these three comment lines. */
    if (context->read_tag != 11 || (uintptr_t)context->read_pointer != 0x1010 ||
        context->write_tag != 22 || (uintptr_t)context->write_pointer != 0x2020 ||
        (uintptr_t)context->epoch_pointer != 0x3030 || context->read_epoch != 33 ||
        context->write_epoch != 44 || context->fast_loads != 55 || context->fast_stores != 66 ||
        context->slow_loads != 77 || context->slow_stores != 88 ||
        (uintptr_t)context->test_probe != 0x4040) return 0;
    return 1;
}
static void *pvm_whole_publish