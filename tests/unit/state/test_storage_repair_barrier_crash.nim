# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Process death during explicitly trusted repair can never invent a recovery token or rollback a complete prefix.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_repairs]
proc main() {.raises.} =
  ## A completed exact-token control precedes every witnessed recovery syscall kill.
  for managed in [false, true]:
    let count = repairCrashCase("repair-barrier-control", managed, syncIo, 4096)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert repairCrashCase("repair-barrier-killed", managed, syncIo, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage_repair_barrier_crash: exact token, actual recovery boundary, strict visible-prefix admission and resumed publication"
