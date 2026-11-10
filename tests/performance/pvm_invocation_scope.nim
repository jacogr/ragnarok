# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One encompassing process-CPU/wall boundary shared by every canonical PVM workload.

import std/[assertions, monotimes, syncio]
import ../../src/pvm/step
import ../support/pvm_owner_record

proc processCpu(): int64 {.importc: "pvm_sieve_cpu_nanoseconds",
    header: "pvm_sieve_clock.h".}
  ## Include all in-process threads; no component clock or worker time is subtracted.

proc copyInvocationInput*(output: var openArray[byte], input {.byref.}: string,
    offset: int) =
  ## Copy a checked fixture span into disjoint caller-owned staging within the invocation.
  assert output.len > 0 and offset >= 0 and offset <= input.len and
      output.len <= input.len - offset
  copyMem(addr output[0], readRawData(input, offset), output.len)

type
  InvocationRuntime* = NativeRuntime
  InvocationClock* = object
    ## Start observations belong to one complete request, never a sum of internal stages.
    cpu*, wall*: int64

proc beginInvocation*(): InvocationClock =
  ## Start before engine-specific input admission or resident reset, without an instance prerequisite.
  let cpu = processCpu()
  InvocationClock(cpu: cpu, wall: getMonoTime().ticks)

proc fullInvocationHeader*() =
  ## Bind current samples to their scope and consume-before-reuse output contract.
  echo "PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu"

proc startInvocationRuntime*(): InvocationRuntime =
  ## Start one application runtime before timing code admission or passing a program.
  result = newNativeRuntime()
  try:
    assert start(result)
  except:
    echo "pvm invocation native runtime startup failed"
    quit 2

proc closeInvocationRuntime*(runtime: var InvocationRuntime, label: string,
    ownerStart: InvocationClock, codeOwners: int = 1) =
  ## Closing/joining is separately observed; the owner window includes driver and oracle work.
  let closing = beginInvocation()
  assert close(runtime)
  runtime = default(InvocationRuntime)
  let stopped = beginInvocation()
  echo "PVM_RUNTIME_OWNER,1,", label, ",application-process,prestarted,", codeOwners
  echo "PVM_RUNTIME_CLOSE,1,", label, ",", stopped.cpu-closing.cpu, ",",
      stopped.wall-closing.wall
  echo "PVM_OWNER_WINDOW,1,", label, ",", stopped.cpu-ownerStart.cpu, ",",
      stopped.wall-ownerStart.wall,
    ",includes-driver-oracles"

proc finishInterpretedOwner*(label: string, ownerStart: InvocationClock, codeOwners: int = 1) =
  ## Interpreted owners have no compiler runtime; observe real retirement without start/close clocks.
  let stopped = beginInvocation()
  echo "PVM_RUNTIME_NONE,1,", label, ",interpreted-policy,", codeOwners
  echo "PVM_OWNER_WINDOW,1,", label, ",", stopped.cpu-ownerStart.cpu, ",",
    stopped.wall-ownerStart.wall, ",includes-driver-oracles"

proc reportNativeCompilation*(label: string, measured: bool, rawNs: uint64) =
  ## Availability is explicit; zero accounting never silently becomes a measured compiler clock.
  echo "PVM_NATIVE_COMPILATION,1,", label, ",", int(measured), ",", rawNs

proc reportInvocationOwner*(prepared: PreparedProgram, label: string) =
  ## Full invocation output observes the owner after guest execution and timing.
  echo invocationOwnerRecord(preparedInfo(prepared).value, label)
