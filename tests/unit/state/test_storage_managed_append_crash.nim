# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed publication process death preserves exact visible bytes and independently checked complete maps.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_appends]
proc main() {.raises.} =
  ## A positive completion counts actual boundaries before each witnessed SIGKILL restart case.
  let count = appendCrashCase("managed-append-control", true, writeIo, 4096)
  assert count == 1
  for skip in 0..<int(count):
    assert appendCrashCase("managed-append-killed", true, writeIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS managed append crash: exact successful boundaries, SIGKILL, authored maps and strict restart"
