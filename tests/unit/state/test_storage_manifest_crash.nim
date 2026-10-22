# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed process death at manifest preserves complete selected state independently from physical reclamation.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_compaction]
proc main() {.raises.} =
  ## A completed positive control counts genuine SDK boundaries before each independently witnessed kill.
  let count = compactionCrashCase("compaction-manifest-control", renameIo, 4096)
  assert count == 1
  for skip in 0..<int(count):
    assert compactionCrashCase("compaction-manifest-killed", renameIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage_manifest_crash: actual manifest rename, strict new epoch and explicit old-epoch cleanup"
