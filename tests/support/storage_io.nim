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
let truncateIo* {.importc: "STORAGE_IO_FTRUNCATE", header: "observer.h".}: cint
  ## Observe only explicit physical truncation, never granting a recovery prefix or rollback point.
proc storageProcessId*(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Supported SDK pid_t is int; fixture names stay process-specific without changing the pinned runtime.
let lockIo* {.importc: "STORAGE_IO_FLOCK", header: "observer.h".}: cint
  ## Observe the actual native lease boundary independently from read/write and durability calls.
let renameIo* {.importc: "STORAGE_IO_RENAMEAT", header: "observer.h".}: cint
  ## Observe native namespace changes independently from data and durability operations.
let unlinkIo* {.importc: "STORAGE_IO_UNLINKAT", header: "observer.h".}: cint
  ## Observe native namespace changes independently from data and durability operations.
let closeIo* {.importc: "STORAGE_IO_CLOSE", header: "observer.h".}: cint
  ## Observe descriptor retirement without introducing production retry behavior.
proc reuseClosedDescriptor*() {.importc: "storage_io_reuse_close", cdecl, header: "observer.h".}
  ## Reuse the exact retired number with a separately owned test resource before returning EINTR.
proc reusedDescriptorOpen*(): cint {.importc: "storage_io_reused_open", cdecl,
    header: "observer.h".}
  ## Prove the caller never accidentally closed the replacement resource by retrying.
proc limitReads*(limit: csize_t) {.importc: "storage_io_read_limit", cdecl, header: "observer.h".}
  ## Cap genuine native read progress; zero restores unrestricted calls and actual EOF.

proc growOnRead*(descriptor: cint, extent: int64): cint {.importc: "storage_io_grow_on_read",
    cdecl, header: "observer.h".}
  ## Borrow this test-owned writable descriptor until reset or one real read grows at most64 KiB.
proc growthPending*(): cint {.importc: "storage_io_growth_pending", cdecl, header: "observer.h".}
  ## Require actual post-stat growth; resetting observation never closes the borrowed fixture handle.
