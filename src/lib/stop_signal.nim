# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scoped SIGINT/SIGTERM handling for a foreground listener; signal context only sets an atomic scalar.

import std/atomics

type
  Handler = proc(number: cint) {.cdecl.} ## Borrowed C signal handler identity; no ARC closure crosses the ABI.
  StopSignals* = object ## Previous process handlers are restored before the foreground owner returns.
    interrupt, terminate: nil Handler
    active: bool

proc `=copy`(destination: var StopSignals, source: StopSignals) {.error.}
  ## A second owner must never restore process handlers belonging to the first owner.
proc `=dup`(source: StopSignals): StopSignals {.error.}
  ## Signal handler ownership cannot be duplicated implicitly.

var stopFlag: cint = 0 ## Signal callbacks cannot allocate, log or touch application owners.
let interruptSignal {.importc: "SIGINT", header: "<signal.h>".}: cint
let terminateSignal {.importc: "SIGTERM", header: "<signal.h>".}: cint
proc install(number: cint, handler: nil Handler): nil Handler {.importc: "signal",
    header: "<signal.h>".}
  ## Use libc's actual signal function signature and preserve the previous callback.
proc requested(number: cint) {.cdecl.} =
  ## Only this lock-free scalar store occurs asynchronously.
  atomicStore(stopFlag, 1)
proc start*(signals: var StopSignals) =
  ## One foreground command owns this process-wide stop request until close.
  atomicStore(stopFlag, 0)
  signals.interrupt = install(interruptSignal, requested)
  signals.terminate = install(terminateSignal, requested)
  signals.active = true
proc stopping*(signals: StopSignals): bool =
  ## Observe interruption on the ordinary dispatcher thread.
  signals.active and atomicLoad(stopFlag) != 0
proc close*(signals: var StopSignals) =
  ## Native callbacks and resources retire through ordinary control flow after interruption.
  if signals.active:
    discard install(interruptSignal, signals.interrupt)
    discard install(terminateSignal, signals.terminate)
    signals.active = false
