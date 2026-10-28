# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded 4096-snapshot vector shares one graph and keeps every exact root/generation alive after close.
import std/assertions
import std/syncio
import ../../support/storage_lifetime_samples
import ../../support/storage_allocations

let baseline = occupiedStorageBytes()
for count in [1024, 8192]:
  # Independent complete-map/value checks and scope retirement remain native assertions.
  let observed = memoryReadersLifetime(count)
  assert observed.checks == count*1+4096
  assert observed.released == observed.baseline
assert occupiedStorageBytes() == baseline
echo "PASS storage readers lifetime"
