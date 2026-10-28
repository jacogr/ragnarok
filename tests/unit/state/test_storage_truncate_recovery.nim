# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Truncation interruption can repeat only the independently exact prefix; permanent refusal grants no owner.
import std/assertions
import std/syncio
import ../../support/storage_repair_faults
proc main() {.raises.} =
  ## Both layouts prove one actual truncation, two resumed interruptions and a separate permanent refusal.
  for managed in [false, true]:
    assert repairCase("storage-truncate-baseline", managed, 0, 0, false, true) == 1
    assert repairCase("storage-truncate-eintr", managed, 0, 2, false, true) == 3
    assert repairCase("storage-truncate-eio", managed, 0, 1, true, true) == 1
try:
  main()
except:
  quit(2)
echo "PASS storage truncate recovery: no implicit authority, exact interrupted extent and permanent refusal"
