# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supervision rejects missed hooks, unmarked stops, early exits and deadlines without losing child ownership.
import std/[assertions, syncio]
import ../../support/[storage_io, storage_crash]
type
  Control = enum ## Each control must retain a different failed-witness or explicit baseline disposition.
    Baseline, UnmarkedStop, EarlyExit, Deadline, Cancelled
let stopSignal {.importc: "SIGSTOP", header: "<signal.h>".}: cint
proc stopNative(signal: cint): cint {.importc: "raise", cdecl, header: "<signal.h>".}
  ## An unrelated kernel stop supplies no observer receipt and must fail verification.
proc idleNative(): cint {.importc: "pause", cdecl, header: "<unistd.h>".}
  ## A child deliberately waiting without an IO hook must hit the parent's monotonic deadline.
proc rawExit(status: cint) {.importc: "_exit", cdecl, header: "<unistd.h>".}
  ## A successful process exit without the explicit observer completion receipt is not a valid baseline.
proc scenario(control: Control) =
  ## Refused controller changes preserve the first exact child; all expected failure paths must reap it.
  defer: abortCrash()
  resetIo()
  assert forkCrash(0, 0) == -1
  assert forkCrash(closeIo+1, 0) == -1
  assert forkCrash(writeIo, -1) == -1 and forkCrash(writeIo, 4097) == -1
  assert startCrash() == -1
  let child = forkCrash(writeIo, 4096)
  assert child >= 0
  if child == 0:
    if forkCrash(writeIo, 0) != -1: exitCrash(70) # Child cannot fork a second supervised descendant.
    if startCrash() != 0 or startCrash() != -1: exitCrash(71)
    case control
    of Baseline: exitCrash(0)
    of UnmarkedStop: discard stopNative(stopSignal)
    of EarlyExit: rawExit(0)
    of Deadline, Cancelled: discard idleNative()
    exitCrash(72)
  assert forkCrash(writeIo, 0) == -1 # Parent cannot replace the first live child or its pipe.
  assert startCrash() == -1
  assert finishCrash(0) == crashInvalid and finishCrash(30001) == crashInvalid
  case control
  of Baseline:
    assert finishCrash() == crashCompleted and crashCount() == 0
  of UnmarkedStop:
    assert finishCrash() == crashInvalid and crashCount() == 0
  of EarlyExit:
    assert finishCrash() == crashError and crashCount() == 0
  of Deadline:
    assert finishCrash(20) == crashTimeout and crashCount() == 0
  of Cancelled:
    abortCrash()
  assert finishCrash() == crashInvalid # Reaped children grant no further ownership of a potentially reused PID.
proc main() =
  ## Repeat all dispositions to expose leaked controller pipes/children rather than relying on process exit.
  for repetition in 0..<4:
    for control in [Baseline, UnmarkedStop, EarlyExit, Deadline, Cancelled]: scenario(control)
main()
echo "PASS storage crash controls: strict receipts, bounded deadlines, exact-child cancellation and reusable ownership"
