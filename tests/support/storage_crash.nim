# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only exact-child supervision binds real successful IO to a witnessed stop and SIGKILL receipt.
let crashKilled* {.importc: "STORAGE_CRASH_KILLED", header: "observer.h".}: cint
let crashCompleted* {.importc: "STORAGE_CRASH_COMPLETED", header: "observer.h".}: cint
let crashInvalid* {.importc: "STORAGE_CRASH_INVALID", header: "observer.h".}: cint
let crashTimeout* {.importc: "STORAGE_CRASH_TIMEOUT", header: "observer.h".}: cint
let crashError* {.importc: "STORAGE_CRASH_ERROR", header: "observer.h".}: cint
proc forkCrash*(operation, skip: cint): cint {.importc: "storage_io_crash_fork", cdecl,
    header: "observer.h".}
  ## Fork one test-owned child and prepare a private fixed-size witness pipe; negative means no child adopted.
proc startCrash*(): cint {.importc: "storage_io_crash_start", cdecl, header: "observer.h".}
  ## Arm the selected child only after setup; a parent cannot arm or change the selected boundary.
proc exitCrash*(status: cint) {.importc: "storage_io_crash_exit", cdecl, header: "observer.h".}
  ## Exit without ARC retirement; zero sends an explicit baseline-completion receipt, never a crash pass.
proc finishCrash*(timeoutMs: cint = 10000): cint {.importc: "storage_io_crash_finish", cdecl,
    header: "observer.h".}
  ## Require exact successful syscall witness, stopped status and SIGKILL reap under monotonic deadlines.
proc abortCrash*() {.importc: "storage_io_crash_abort", cdecl, header: "observer.h".}
  ## Kill/reap only the exact owned child on parent fixture failure; never retry a retired PID.
proc crashCount*(): uint64 {.importc: "storage_io_crash_count", cdecl, header: "observer.h".}
  ## Inspect only a validated child receipt's actual successful-operation count.
