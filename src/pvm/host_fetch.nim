# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Evaluate fetch for present entropy and authorizer-trace values with bounded atomic memory copies.
## FetchEntropy types the fixed entropy input; FetchResult separates local refusals from completed Continue, Panic and OutOfGas responses.
## Inputs are borrowed only during the call; returned memory owns copies. See spec/pvm-fetch-bytes.md.

import ./[machine, step]

type
  # Invocation entropy is one nominal 32-byte value, distinct from arbitrary trace bytes.
  FetchEntropy* = distinct array[32, byte]
  # Local misuse and resource policy are not guest-visible host exits.
  FetchError* {.pure.} = enum
    Uninitialized, None, UnsupportedSelector, InvalidMemory, LimitExceeded
  # Private tagged alternatives prevent reading a response after a local refusal.
  FetchResult* = object
    case status: FetchError
    of None:
      # The response retains immutable memory and copies registers; no borrowed input escapes.
      completed: HostResponse
    else:
      # Failure carries no partly charged response or partial copy.
      discard

# Inspect a result without exposing mutable variant storage.
func error*(r: FetchResult): FetchError = r.status
# Select a completed protocol outcome only after checking success.
func value*(r: FetchResult): HostResponse {.requires: r.status == FetchError.None.} = r.completed

# Apply the present-value branch after the public wrapper chooses its fixed selector and prices.
# Caller bytes must remain stable during this synchronous call; the source memory is immutable.
proc fetchPresent(gas: MachineGas, registers: RegisterFile, memory: Memory,
    bytes: openArray[byte], selector, base, rate: uint64, limit: MemoryByteLimit): FetchResult =
  if uint64(registers[10]) != selector:
    # A known but unimplemented selector must never become an unknown/absent-value response.
    return FetchResult(status: FetchError.UnsupportedSelector)
  if pageImage(memory, PageIndex(0)).error != MachineError.None:
    # Reject default owners even when gas is insufficient or the clipped copy would be empty.
    return FetchResult(status: FetchError.InvalidMemory)
  let requested = uint64(registers[9])
  # Splitting before multiplication computes ceil(rate*z/1024) for all uint64 z without overflow.
  # Private callers use rate <= 96 and base <= 103, so the total and any deficit fit signed 64 bits.
  let cost = base + (requested div 1024) * rate + ((requested mod 1024) * rate + 1023) div 1024
  if uint64(gas) < cost:
    # General-host underfunding takes precedence over guest memory and local copy-size checks.
    return FetchResult(status: FetchError.None, completed: HostResponse(
      action: HostAction.OutOfGas, gas: MachineGas(0), gasDeficit: GasDeficit(cost - uint64(gas)),
      registers: registers, memory: memory))
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(uint64(gas) - cost),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)
  let offset = min(uint64(registers[8]), uint64(bytes.len))
  let count = min(requested, uint64(bytes.len) - offset)
  # Clipping to the existing borrowed span proves both conversions and the inclusive end safe.
  var written = default(MachineResult[Memory])
  if count == 0:
    # Empty natural intervals permit every pointer; avoid constructing an inverted borrowed slice.
    written = writeBytes(memory, MemoryAddress(uint64(registers[7])), [], limit)
  else:
    # writeBytes preflights the whole destination and never exposes a writable partial prefix.
    written = writeBytes(memory, MemoryAddress(uint64(registers[7])),
      bytes.toOpenArray(int(offset), int(offset + count - 1)), limit)
  case written.error
  of MachineError.None:
    # Return the complete selected value length, not the requested or copied length.
    response.memory = written.value
    response.registers[7] = RegisterValue(uint64(bytes.len))
  of MachineError.Fault, MachineError.InvalidRange:
    # The fetch table maps unwritable natural ranges to Panic, retaining r7 and all memory.
    response.action = HostAction.Panic
  of MachineError.LimitExceeded:
    # Local copy policy cannot manufacture a protocol panic; no response escapes this refusal.
    return FetchResult(status: FetchError.LimitExceeded)
  else:
    # Valid owner/range inputs cannot produce another memory failure; retain an explicit local guard.
    return FetchResult(status: FetchError.InvalidMemory)
  FetchResult(status: FetchError.None, completed: response)

# Fetch selector 1 with present 32-byte entropy: fixed cost 103, independent of requested length.
# Dispatcher supplies the invocation's entropy and host identifier 2; absence is outside this API.
proc fetchEntropyResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    entropy: FetchEntropy, limit: MemoryByteLimit): FetchResult =
  fetchPresent(gas, registers, memory, array[32, byte](entropy), 1, 103, 0, limit)

# Fetch selector 2 with a present trace (including empty): cost 80 + ceil(96*r9/1024).
# This does not select invocation context. A local failure must be propagated by the dispatcher,
# never converted to HostAction.Panic; executeWithHost's response-only callback cannot carry it.
proc fetchTraceResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    trace: openArray[byte], limit: MemoryByteLimit): FetchResult =
  fetchPresent(gas, registers, memory, trace, 2, 80, 96, limit)
