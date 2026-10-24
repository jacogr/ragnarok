# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Group every real light publication boundary with successful controls, exact-child death and retained proof semantics.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_light_crash]
proc main() {.raises.} =
  ## Control counts determine exhaustive independent kill points for full/short writes, syncs, rename and staged close.
  for operation in [writeIo, syncIo, renameIo, closeIo]:
    let count = lightPublicationCrash(operation, 4096)
    let expected = if operation == syncIo: 2'u64 else: 1'u64
    assert count == expected
    for skip in 0..<int(count):
      assert lightPublicationCrash(operation, cint(skip)) == uint64(skip)+1
  let shortCount = lightPublicationCrash(writeIo, 4096, true)
  assert shortCount > 1 and shortCount < 32
  for skip in 0..<int(shortCount):
    assert lightPublicationCrash(writeIo, cint(skip), true) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage light publication crashes: every actual boundary, exact staged prefixes, held leases and strict old/new recovery"
