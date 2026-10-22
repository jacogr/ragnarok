# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Process death during explicitly trusted repair can never invent a recovery token or rollback a complete prefix.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_repairs]
proc main() {.raises.} =
  ## A completed exact-token control precedes every witnessed recovery syscall kill.
  assert repairCrashCase("storage_managed_repair_crash-control", true, truncateIo, 4096) == 1
  assert repairCrashCase("storage_managed_repair_crash-killed", true, truncateIo, 0) == 1
try:
  main()
except:
  quit(2)
echo "PASS storage_managed_repair_crash: exact token, actual recovery boundary, strict visible-prefix admission and resumed publication"
