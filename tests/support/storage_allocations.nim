# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only allocator observations distinguish live Nim heap bytes from whole-process peak RSS.
import std/assertions
import std/syncio

proc occupiedStorageBytes*(): int =
  ## Observe the current Nim allocator; stack, native-library buffers and OS page cache are excluded.
  result = getOccupiedMem()
  assert result >= 0

proc emitStorageAllocation*(phase: string) =
  ## Capture before formatting so the output string itself cannot enter the recorded checkpoint.
  let occupied = occupiedStorageBytes()
  echo "allocation\t", phase, "\t", occupied
