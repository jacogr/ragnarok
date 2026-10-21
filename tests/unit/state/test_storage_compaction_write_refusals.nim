# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed snapshot, journal or staged-manifest writes cannot select an incomplete epoch.
import std/[assertions, syncio]
import ../../support/storage_compaction_faults
proc main() {.raises.} =
  ## Each compacted fixture has exactly three complete staged writes before manifest selection.
  let writes = compactionCase("storage-compact-write-baseline", 0, 0, false, true)
  assert writes == 3
  for skip in 0..<int(writes):
    discard compactionCase("storage-compact-write-eio", cint(skip), 1, true, true)
try:
  main()
except:
  quit(2)
echo "PASS storage compaction write refusals: staged snapshot/journal/manifest, unchanged CURRENT and strict restart"
