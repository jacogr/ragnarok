# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Killing after each actual staged write cannot select an unrenamed managed manifest.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_compaction]
proc main() {.raises.} =
  ## Snapshot, journal and pending manifest are separately complete writes before atomic selection.
  assert compactionCrashCase("compaction-write-control", writeIo, 4096) == 3
  for skip in 0..<3:
    assert compactionCrashCase("compaction-write-killed", writeIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS compaction write crash: exact old selection, forensic staging, strict restart and explicit retry"
