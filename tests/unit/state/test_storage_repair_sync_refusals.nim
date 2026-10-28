# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused repair confirmation preserves visible progress without inventing a successful live owner.
import std/assertions
import std/syncio
import ../../support/storage_repair_faults
proc main() {.raises.} =
  ## Every real file/namespace barrier fails independently before strict visibility and exact-token resumption.
  for managed in [false, true]:
    let barriers = repairCase("storage-repair-refusal-baseline", managed, 0, 0)
    assert barriers > 0 and barriers < 32
    for skip in 0..<int(barriers):
      discard repairCase("storage-repair-eio", managed, cint(skip), 1, true)
try:
  main()
except:
  quit(2)
echo "PASS storage repair sync refusals: no live uncertainty, visible truncation retained and exact-token confirmation"
