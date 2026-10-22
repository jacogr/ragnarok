# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only bounded native IO observation; callers reset before fixture IO and verify consumed faults.
import std/assertions
let readIo* {.importc: "STORAGE_IO_READ", header: "observer.h".}: cint
let writeIo* {.importc: "STORAGE_IO_WRITE", header: "observer.h".}: cint
let syncIo* {.importc: "STORAGE_IO_FSYNC", header: "observer.h".}: cint
let interruptedIo* {.importc: "EINTR", header: "<errno.h>".}: cint
let failedIo* {.importc: "EIO", header: "<errno.h>".}: cint
proc resetIo*() {.importc: "storage_io_reset", cdecl, header: "observer.h".}
  ## Remove every pending injected refusal and short-write cap.
proc configure(operation, skip, failures, reason: cint): cint {.importc: "storage_io_arm", cdecl,
    header: "observer.h".}
  ## The C controller rejects invalid operations and negative fault counts without changing SDK state.
proc ioCalls*(operation: cint): uint64 {.importc: "storage_io_calls", cdecl, header: "observer.h".}
  ## Count actual calls reaching the selected test observer.
proc pendingIo*(): cint {.importc: "storage_io_remaining", cdecl, header: "observer.h".}
  ## Require configured faults to be consumed, rather than treating an unexercised case as success.
proc limitWrites*(limit: csize_t) {.importc: "storage_io_write_limit", cdecl, header: "observer.h".}
  ## Request genuine short native writes; zero restores unrestricted forwarding.
proc armIo*(operation: cint, skip, failures: cint, reason: cint) =
  ## A bounded controller is test infrastructure, never a production failure or policy switch.
  assert configure(operation, skip, failures, reason) == 0
proc zeroWrites*(skip, count: cint): cint {.importc: "storage_io_zero_writes", cdecl,
    header: "observer.h".}
  ## Bounded zero-progress controls never write bytes or invent a successful positive extent.
proc pendingZeroWrites*(): cint {.importc: "storage_io_zero_remaining", cdecl,
    header: "observer.h".}
  ## Require intended zero-progress outcomes to be consumed by the real storage write loop.
