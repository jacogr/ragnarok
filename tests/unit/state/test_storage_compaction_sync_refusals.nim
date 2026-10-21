# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A refused epoch barrier must retain uncertainty or an explicit confirmed-selection cleanup receipt.
import std/[assertions, syncio]
import ../../support/storage_compaction_faults
proc main() {.raises.} =
  ## Every observed real barrier has one independent EIO case with complete-map strict restart.
  let barriers = compactionCase("storage-compact-refusal-baseline", 0, 0)
  assert barriers > 0 and barriers < 32
  for skip in 0..<int(barriers):
    discard compactionCase("storage-compact-eio", cint(skip), 1, true)
try:
  main()
except:
  quit(2)
echo "PASS storage compaction sync refusals: every boundary, explicit uncertainty, confirmed cleanup and strict restart"
