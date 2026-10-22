# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Allocator checkpoints observe live test-owned payloads and return to baseline after ARC retirement.
import std/[assertions, syncio]
import ../../support/storage_allocations

proc retainedPayload(): int =
  ## Keep every payload live at the observation and explicitly consume its last byte afterward.
  let before = occupiedStorageBytes()
  var payload = newSeq[byte](16384)
  payload[16383] = 91
  let during = occupiedStorageBytes()
  assert during >= before+16384
  assert payload[16383] == 91
  result = during-before

let baseline = occupiedStorageBytes()
for cycle in 0..<100:
  # Repeated isolated scopes establish actual retirement, rather than a metadata-only assertion.
  assert retainedPayload() >= 16384
assert occupiedStorageBytes() == baseline
echo "PASS storage allocator checkpoints"
