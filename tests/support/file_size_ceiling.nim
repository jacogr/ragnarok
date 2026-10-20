# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Child-only real kernel file-size refusal setup shared by synchronous-bank and native-worker witnesses.

type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Supported 64-bit Linux/macOS SDK fields retain their exact C names and native structure.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## A nonallocating C callback keeps a size violation observable as write refusal.

let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Inspect the inherited hard ceiling before changing the child's soft file-size limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Restrict only this child; no parent/global resource budget is changed.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Keep the real kernel size violation as a return value instead of process termination.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## The signal handler performs no allocation, output or state access.
  discard

proc restrictFileSize*(ceiling: uint64): cint =
  ## Call only in a fresh child before creating workers; preserve inherited hard limits and return distinct setup failures.
  var limits = default(ResourceLimit)
  if getLimit(fileLimit, addr limits) != 0 or ceiling > limits.maximum:
    return 3 # Resource setup cannot masquerade as a typed write refusal.
  let previous = install(sizeSignal, ignore)
  if previous == signalError: return 4 # Signal termination is not the I/O-return-value contract under test.
  limits.current = ceiling
  if setLimit(fileLimit, addr limits) != 0: return 5 # Only this child process and its later threads receive the soft ceiling.
  0
