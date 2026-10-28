# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A killed multi-publication writer leaves one exact complete prefix without losing earlier confirmed frames.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_sequences
proc main() {.raises.} =
  ## Count four actual frame writes and twelve real barriers, then kill independently after every one.
  for operation in [writeIo, syncIo]:
    let count = sequenceCrashCase("managed-sequence-control", true, operation, 4096)
    assert count == (if operation == writeIo: 4'u64 else: 12'u64)
    for skip in 0..<int(count):
      assert sequenceCrashCase("managed-sequence-killed", true, operation, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS managed sequence crash: every real write/barrier, exact complete prefix and historical authored maps"
