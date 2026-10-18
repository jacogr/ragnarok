# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture the GP 0.8.0 argument-invocation return buffer from an already halted machine.
## Exposes OutputByteLimit, OutputError/Result and captureOutput. Successful byte sequences are
## independent copies; unreadable guest ranges produce empty output. See spec/pvm-output.md.

import ./[machine, step]

type
  # Local copying policy is independent of guest register lengths, gas and physical memory addresses.
  OutputByteLimit* = distinct uint64
  # Guest unreadability is successful empty output; only local misuse/policy refusals fail this API.
  OutputError* {.pure.} = enum
    Uninitialized, None, NotHalted, InvalidMachine, LimitExceeded
  # Failed/default alternatives expose neither output bytes nor a completed-prefix count.
  OutputResult* = object
    case status: OutputError
    of None:
      # Seq ownership is copied on extraction; no mutable memory-page reference escapes.
      completed: seq[byte]
    else:
      # Failure reasons alone are observable without selecting success.
      discard

# Read status without permitting result forgery or retagging.
func error*(r: OutputResult): OutputError = r.status
# Return an independently owned byte sequence only after selecting successful extraction.
func value*(r: OutputResult): seq[byte] {.requires: r.status == OutputError.None.} = r.completed

# Apply only Psi_M's halt return-buffer rule; execution, host dispatch and gas accounting are separate.
proc captureOutput*(outcome: StepOutcome, limit: OutputByteLimit): OutputResult =
  # Host/fault/panic/out-of-gas and unfinished steps must not be converted into successful returns.
  if outcome.exit != StepExit.Halt:
    return OutputResult(status: OutputError.NotHalted)
  let info = machineInfo(outcome.machine)
  let memory = memoryOf(outcome.machine)
  # A caller may replace the public machine handle on a copied outcome; validate both owned children.
  if info.error != MachineError.None or memory.error != MachineError.None:
    return OutputResult(status: OutputError.InvalidMachine)
  if uint64(info.value.gasDeficit) != 0:
    # Replacing a Halt handle with a negative-gas terminal owner cannot fabricate successful output.
    return OutputResult(status: OutputError.InvalidMachine)
  let start = uint64(info.value.registers[7])
  let length = uint64(info.value.registers[8])
  # The empty natural interval is readable for every pointer, including UINT64_MAX.
  if length == 0:
    return OutputResult(status: OutputError.None, completed: @[])
  # This interval is natural, not cyclic. Check by subtraction before forming its exclusive end.
  if start >= 0x100000000'u64 or length > 0x100000000'u64 - start:
    return OutputResult(status: OutputError.None, completed: @[])
  let last = start + length - 1
  var page = start div 4096
  # Preflight the entire interval before copying: a readable prefix never becomes a partial result.
  while page <= last div 4096:
    let image = pageImage(memory.value, PageIndex(uint32(page)))
    if image.error != MachineError.None:
      # Owned physical-page lookup cannot fail after the address bounds above, except for API corruption.
      return OutputResult(status: OutputError.InvalidMachine)
    if image.value.access == PageAccess.Inaccessible:
      # Inaccessible retained bytes and absent pages both satisfy the GP empty-return branch.
      return OutputResult(status: OutputError.None, completed: @[])
    inc page
  # Only a readable range requires materialization; an oversized unreadable range still returns empty.
  if length > uint64(limit):
    return OutputResult(status: OutputError.LimitExceeded)
  var bytes = newSeq[byte](int(length))
  var copied = 0'u64
  # Immutable pages cannot change between preflight and copy; each image is read once per pass.
  while copied < length:
    let address = start + copied
    let image = pageImage(memory.value, PageIndex(uint32(address div 4096))).value
    let offset = int(address mod 4096)
    let count = min(int(length - copied), 4096 - offset)
    for i in 0..<count:
      # The final chunk is clipped to the requested interval, never to a caller's larger buffer.
      bytes[int(copied) + i] = image.bytes[offset + i]
    copied += uint64(count)
  OutputResult(status: OutputError.None, completed: bytes)
