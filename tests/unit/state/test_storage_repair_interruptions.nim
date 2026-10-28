# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every explicit-repair durability boundary must complete after interruption without widening prefix authority.
import std/assertions
import std/syncio
import ../../support/storage_repair_faults
proc main() {.raises.} =
  ## Count each backend's genuine barriers, then interrupt them independently after a real torn append.
  for managed in [false, true]:
    let barriers = repairCase("storage-repair-baseline", managed, 0, 0)
    assert barriers > 0 and barriers < 32
    for skip in 0..<int(barriers):
      assert repairCase("storage-repair-eintr", managed, cint(skip), 2) == barriers+2
try:
  main()
except:
  quit(2)
echo "PASS storage repair interruptions: real torn appends, every durability boundary and exact trusted prefix"
