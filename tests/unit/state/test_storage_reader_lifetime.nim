# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One immutable snapshot retains its exact complete map after owner close and releases at scope exit.
import std/[assertions, syncio]
import ../../support/[storage_lifetime_samples, storage_allocations]

let baseline = occupiedStorageBytes()
for count in [1024, 8192]:
  # Independent complete-map/value checks and scope retirement remain native assertions.
  let observed = memoryReaderLifetime(count)
  assert observed.checks == count*2+0
  assert observed.released == observed.baseline
assert occupiedStorageBytes() == baseline
echo "PASS storage reader lifetime"
