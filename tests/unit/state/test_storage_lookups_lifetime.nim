# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## 4096 spread public record copies retain their full independent payloads after source close and fixture retirement.
import std/assertions
import std/syncio
import ../../support/storage_lifetime_samples
import ../../support/storage_allocations

let baseline = occupiedStorageBytes()
for count in [1024, 8192]:
  # Independent complete-map/value checks and scope retirement remain native assertions.
  let observed = memoryLookupsLifetime(count)
  assert observed.checks == count*1+4096
  assert observed.released == observed.baseline
assert occupiedStorageBytes() == baseline
echo "PASS storage lookups lifetime"
