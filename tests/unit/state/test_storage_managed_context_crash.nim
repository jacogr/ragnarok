# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque context follows exactly the same complete-prefix authority as its authored selected root.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash_appends]
proc main() {.raises.} =
  ## Complete writes/barriers and torn/final extents must never mix old context with a new root or vice versa.
  for operation in [writeIo, syncIo]:
    let label = "managed-context-" & $operation
    let count = appendCrashCase(label & "-control", true, operation, 4096, false, true)
    assert count > 0 and count <= 3
    for skip in 0..<int(count):
      assert appendCrashCase(label & "-killed", true, operation, cint(skip), false, true) == uint64(skip)+1
  let count = appendCrashCase("managed-context-partial-control", true, writeIo, 4096, true, true)
  assert count > 4
  for skip in [0, int(count)-1]:
    assert appendCrashCase("managed-context-partial-killed", true, writeIo, cint(skip), true,
        true) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS managed context crash: exact root/context prefixes, independent repair and complete successor authority"
