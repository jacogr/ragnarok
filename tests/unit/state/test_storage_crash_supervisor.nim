# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A passing process-crash witness requires a real successful OS write, exact stop and SIGKILL reap.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash]
proc openNative(path: cstring, flags: cint): cint {.importc: "open", cdecl, header: "<fcntl.h>".}
  ## A harmless real SDK descriptor is enough to prove process-control boundaries before storage scenarios.
let writeOnly {.importc: "O_WRONLY", header: "<fcntl.h>".}: cint
proc observedWrite(fd: cint, data: pointer, size: csize_t): clong {.importc: "storage_io_write",
    cdecl, header: "observer.h".}
  ## This calls the actual same C observer used by native storage writes.
proc main() =
  ## Zero and one skipped success must produce different exact receipts; a high skip is a normal baseline.
  defer: abortCrash()
  for skip in [0, 1, 4096]:
    resetIo()
    let child = forkCrash(writeIo, cint(skip))
    assert child >= 0
    if child == 0:
      let descriptor = openNative("/dev/null", writeOnly)
      if descriptor < 0 or startCrash() != 0: exitCrash(71)
      var value = 9'u8
      for index in 0..<3:
        if observedWrite(descriptor, addr value, 1) != 1: exitCrash(72)
      exitCrash(0)
      exitCrash(73) # Unreachable even for a normally completing baseline; no ARC/destructor path is accepted.
    let status = finishCrash()
    if skip == 4096:
      assert status == crashCompleted and crashCount() == 3
    else:
      assert status == crashKilled and crashCount() == uint64(skip)+1
  assert finishCrash() == crashInvalid
main()
echo "PASS storage crash supervisor: real successful writes, exact stopped witness and SIGKILL reap"
