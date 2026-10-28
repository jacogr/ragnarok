# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary owner measurements retire prepared fixtures before observing complete repository retention.
import std/assertions
import std/syncio
import ../../support/storage_lifetime_samples
import ../../support/storage_allocations

let before = occupiedStorageBytes()
for count in [1024, 8192]:
  # Every map entry is independently checked; no fixture graph or reader escapes the measurement.
  let observed = memoryOwnerLifetime(count)
  assert observed.checks == count and observed.fixture == -1 and observed.held == -1
  assert observed.owner > observed.baseline and observed.closed == observed.baseline
  assert observed.released == observed.baseline
assert occupiedStorageBytes() == before
echo "PASS storage owner lifetime"
