# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed process death at barriers preserves complete selected state independently from physical reclamation.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_compaction
proc main() {.raises.} =
  ## A completed positive control counts genuine SDK boundaries before each independently witnessed kill.
  let count = compactionCrashCase("compaction-barriers-control", syncIo, 4096)
  assert count > 0 and count < 32
  for skip in 0..<int(count):
    assert compactionCrashCase("compaction-barriers-killed", syncIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage_compaction_barrier_crash: every real replacement barrier, one strict selected epoch and retained readers"
