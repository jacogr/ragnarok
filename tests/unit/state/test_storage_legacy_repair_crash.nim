# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Process death during explicitly trusted repair can never invent a recovery token or rollback a complete prefix.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_repairs
proc main() {.raises.} =
  ## A completed exact-token control precedes every witnessed recovery syscall kill.
  assert repairCrashCase("storage_legacy_repair_crash-control", false, truncateIo, 4096) == 1
  assert repairCrashCase("storage_legacy_repair_crash-killed", false, truncateIo, 0) == 1
try:
  main()
except:
  quit(2)
echo "PASS storage_legacy_repair_crash: exact token, actual recovery boundary, strict visible-prefix admission and resumed publication"
