# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained historical root unions and opaque current context survive every managed replacement phase.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_compaction
proc main() {.raises.} =
  ## Every staged write, sync, atomic rename and retired unlink must preserve both complete authored roots.
  for operation in [writeIo, syncIo, renameIo, unlinkIo]:
    let count = compactionCrashCase("history-compaction-control", operation, 4096, false, true)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert compactionCrashCase("history-compaction-killed", operation, cint(skip), false, true) ==
          uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS history compaction crash: every replacement phase, retained complete roots and exact opaque context"
