/* Copyright (c) 2026 Ragnarök contributors */
/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Private owned ABI fragment; the projector removes exactly these three comment lines. */
_Static_assert(offsetof(pvm_whole_invocation, read_tag) == 160, "read lease ABI");
_Static_assert(offsetof(pvm_whole_invocation, epoch_pointer) == 192, "epoch ABI");
_Static_assert(offsetof(pvm_whole_invocation, fast_loads) == 216, "native count ABI");
_Static_assert(offsetof(pvm_whole_invocation, test_probe) == 248, "probe ABI");
_Static_assert(sizeof(pvm_whole_invocation)