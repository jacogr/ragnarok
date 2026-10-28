# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every actual short staged write preserves exact authored file prefixes and cannot select incomplete staging.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_compaction
proc main() {.raises.} =
  ## Bound the complete three-file control, then kill after every eight-byte snapshot/journal/manifest write.
  let count = compactionCrashCase("staged-partial-control", writeIo, 4096, true)
  assert count > 3 and count < 256
  for skip in 0..<int(count):
    assert compactionCrashCase("staged-partial-killed", writeIo, cint(skip), true) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS staged partial crash: every genuine short write, exact authored prefixes, old selection and explicit retry"
