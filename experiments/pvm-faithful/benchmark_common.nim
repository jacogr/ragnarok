# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Measurement-only helpers shared by the fresh drivers. No production PVM execution,
## memory, decoder, gas or lifetime implementation is imported.

import std/[assertions, monotimes, syncio, envvars]

proc processCpu(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
  ## Reuse the canonical harness's checked process CPU clock, including all process threads.

type Clock* = object
  ## Both observations delimit one encompassing invocation; no component subtraction.
  cpu*, wall*: int64

proc begin*(): Clock =
  ## Start CPU before wall exactly as the canonical direct interpreter embedding does.
  let cpu = processCpu()
  Clock(cpu: cpu, wall: getMonoTime().ticks)

proc elapsed*(start: Clock): Clock =
  ## Stop wall then CPU, after normal result materialization and before oracle work.
  let wall = getMonoTime().ticks-start.wall
  Clock(cpu: processCpu()-start.cpu, wall: wall)

proc word*(data: string, at, width: int): uint64 =
  ## Read fixed little-endian fields only after proving the complete field extent.
  assert at >= 0 and width >= 0 and width <= 8 and at <= data.len and width <= data.len-at
  result = 0
  for index in 0..<width: result = result or (uint64(byte(data[at+index])) shl (8*index))

proc local*(path: string): string =
  ## Missing fixture input is a failed experiment, never an empty timing observation.
  try: result = readFile(path)
  except: quit 2

proc header*() =
  ## A requested JIT role explicitly aliases this same interpreter implementation.
  let role = getEnv("RAGNAROK_PVM_BACKEND", "interpreted")
  assert role in ["interpreted", "jit"]
  echo "PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu"
  echo "FAITHFUL_ENGINE,1,", role, ",interpreter,0"

proc report*(label: string, sample: int, time: Clock, cache: uint64) =
  ## Publish only after complete validation; qualification remains the orchestrator's responsibility.
  if getEnv("RAGNAROK_FAITHFUL_CORRECTNESS_ONLY") == "1":
    echo "FAITHFUL_VALIDATED,1,", label, ",", sample, ",", cache
    return
  assert time.cpu > 0 and time.wall > 0, "faithful invocation clock below resolution"
  echo "FAITHFUL_SAMPLE,1,", label, ",", sample, ",", time.cpu, ",", time.wall, ",", cache
