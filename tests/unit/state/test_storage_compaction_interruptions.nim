# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every actual epoch-replacement barrier resumes through consumed interruptions before success.
import std/assertions
import std/syncio
import ../../support/storage_compaction_faults
proc main() {.raises.} =
  ## Count genuine baseline barriers, then interrupt each individually without changing selected state.
  let barriers = compactionCase("storage-compact-baseline", 0, 0)
  assert barriers > 0 and barriers < 32
  for skip in 0..<int(barriers):
    assert compactionCase("storage-compact-eintr", cint(skip), 2) == barriers+2
try:
  main()
except:
  quit(2)
echo "PASS storage compaction interruptions: every real file/namespace barrier, strict reopen and held views"
