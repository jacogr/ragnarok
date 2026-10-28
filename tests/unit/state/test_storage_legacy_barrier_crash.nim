# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real legacy publication process death preserves exact visible bytes and independently checked complete maps.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_appends
proc main() {.raises.} =
  ## A positive completion counts actual boundaries before each witnessed SIGKILL restart case.
  let count = appendCrashCase("legacy-barrier-control", false, syncIo, 4096)
  assert count == 3
  for skip in 0..<int(count):
    assert appendCrashCase("legacy-barrier-killed", false, syncIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS legacy barrier crash: exact successful boundaries, SIGKILL, authored maps and strict restart"
