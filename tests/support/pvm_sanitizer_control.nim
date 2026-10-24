# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberate sanitizer controls never execute from ordinary native test discovery.
import std/[assertions, syncio, envvars]
proc rawRead(bytes: ptr byte, offset: uint64): byte {.importc: "pvm_sanitizer_read",
    header: "pvm_sanitizer_control.h".}
  ## Verification-only raw addressing bypasses Nim's logical bounds check for the requested negative witness.
proc heapRead(dangling: byte): byte {.importc: "pvm_sanitizer_heap",
    header: "pvm_sanitizer_control.h".}
  ## Verification-only C allocation supplies a separately classified use-after-free witness.
proc control(mode: string) =
  ## Positive reads and two intentional failures use the same compiler profile and instrumentation.
  assert mode in ["positive", "stack", "heap"]
  var bytes = default(array[8, byte])
  bytes[0] = 42
  let offset = if mode == "stack": 8'u64 else: 0'u64
  assert rawRead(addr bytes[0], offset) == 42
  assert heapRead(byte(if mode == "heap": 1 else: 0)) == 42
  echo "PVM sanitizer positive passed"
control(getEnv("RAGNAROK_PVM_SANITIZER_CONTROL"))
