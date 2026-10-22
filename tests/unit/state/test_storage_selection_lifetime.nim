# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An opaque selected-root plan retains its exact immutable source and permits a complete independent clone after close.
import std/[assertions, syncio]
import ../../support/[storage_lifetime_samples, storage_allocations]

let baseline = occupiedStorageBytes()
for count in [1024, 8192]:
  # Independent complete-map/value checks and scope retirement remain native assertions.
  let observed = memorySelectionLifetime(count)
  assert observed.checks == count*1+0
  assert observed.released == observed.baseline
assert occupiedStorageBytes() == baseline
echo "PASS storage selection lifetime"
