# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture the GP 0.8.0 argument-invocation return buffer from an already halted machine.
## Exposes OutputByteLimit, OutputError/Result and captureOutput. Successful byte sequences are
## independent copies; unreadable guest ranges produce empty output. See spec/pvm-output.md.

import ./[machine, step]

type
  OutputByteLimit* = distinct uint64 ## Local copying policy is independent of guest register lengths, gas and physical memory addresses.
  OutputError* {.pure.} = enum ## Guest unreadability is successful empty output; only local misuse/policy refusals fail this API.
    Uninitialized, None, NotHalted, InvalidMachine, LimitExceeded
  OutputResult* = object ## Failed/default alternatives expose neither output bytes nor a completed-prefix count.
    case status: OutputError
    of None:
      # Seq ownership is copied on extraction; no mutable memory-page reference escapes.
      completed: seq[byte]
    else:
      # Failure reasons alone are observable without selecting success.
      discard

func error*(r: OutputResult): OutputError =
  ## Read status without permitting result forgery or retagging.
  r.status

func value*(r: OutputResult): seq[byte] {.requires: r.status == OutputError.None.} =
  ## Return an independently owned byte sequence only after selecting successful extraction.
  r.completed

proc captureOutput*(outcome: StepOutcome, limit: OutputByteLimit): OutputResult =
  ## Apply only Psi_M's halt return-buffer rule; execution, host dispatch and gas accounting are separate.
  # Host/fault/panic/out-of-gas and unfinished steps must not be converted into successful returns.
  if outcome.exit != StepExit.Halt:
    return OutputResult(status: OutputError.NotHalted)
  let info = machineInfo(outcome.machine)
  # A caller may replace the public machine handle on a copied outcome.
  if info.error != MachineError.None:
    return OutputResult(status: OutputError.InvalidMachine)
  if uint64(info.value.gasDeficit) != 0:
    # Replacing a Halt handle with a negative-gas terminal owner cannot fabricate successful output.
    return OutputResult(status: OutputError.InvalidMachine)
  let length = uint64(info.value.registers[8])
  # The empty natural interval is readable for every pointer, including UINT64_MAX.
  if length == 0:
    return OutputResult(status: OutputError.None, completed: @[])
  let memory = memoryOf(outcome.machine)
  if memory.error != MachineError.None:
    return OutputResult(status: OutputError.InvalidMachine)
  let start = MemoryAddress(uint64(info.value.registers[7]))
  if length > uint64(limit):
    # An oversized unreadable interval still returns empty. Inspect permissions without copying.
    let checked = readableRange(memory.value, start, MemoryLength(length))
    case checked.error
    of MachineError.None: return OutputResult(status: OutputError.LimitExceeded)
    of MachineError.Fault, MachineError.InvalidRange:
      return OutputResult(status: OutputError.None, completed: @[])
    else: return OutputResult(status: OutputError.InvalidMachine)
  # Preflight the natural interval, then copy only the requested bytes into their final owner.
  var captured = readBytes(memory.value, start, MemoryLength(length), MemoryByteLimit(uint64(limit)))
  case captured.error
  of MachineError.None: OutputResult(status: OutputError.None, completed: takeValue(captured))
  of MachineError.Fault, MachineError.InvalidRange:
    OutputResult(status: OutputError.None, completed: @[])
  of MachineError.LimitExceeded: OutputResult(status: OutputError.LimitExceeded)
  else: OutputResult(status: OutputError.InvalidMachine)
