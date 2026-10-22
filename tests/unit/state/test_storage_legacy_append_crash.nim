# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Legacy complete writes remain strictly decodable when a writer dies before receiving its syscall result.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_appends]
proc main() {.raises.} =
  ## Count a genuine completed control, then kill at its actual complete append write.
  assert appendCrashCase("legacy-append-control", false, writeIo, 4096) == 1
  assert appendCrashCase("legacy-append-killed", false, writeIo, 0) == 1
try:
  main()
except:
  quit(2)
echo "PASS legacy append crash: actual successful write, SIGKILL, exact complete frame and strict restart"
