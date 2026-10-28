# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real short append process death requires strict refusal and independent exact-prefix recovery.
import std/assertions
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash_appends
proc main() {.raises.} =
  ## Initial, middle, penultimate and final real writes cover incomplete tails and a complete successor.
  let count = appendCrashCase("legacy-partial-control", false, writeIo, 4096, true)
  assert count > 4 and count < 4096
  for skip in [0, int(count div 2), int(count)-2, int(count)-1]:
    assert appendCrashCase("legacy-partial-killed", false, writeIo, cint(skip), true) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS legacy partial crash: exact real progress, strict refusal, independent prefix repair and no complete rollback"
