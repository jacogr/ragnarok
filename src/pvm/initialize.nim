# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standard GP 0.8.0 JAM envelope and memory initialization, followed by validated machine capture.
## Exposes InitializationLimits, InitializationError/Result and initializeMachine. Inputs are borrowed
## only during the call; successful machines own immutable acyclic copies. See spec/pvm-initialization.md.

import ./[program, machine]
import ../codec/bounded

type
  InitializationByteLimit* = distinct uint64 ## Local input policy bounds the complete JAM envelope independently of the embedded program.
  InitializationLimits* = object ## Independent local allocation and decoding ceilings never change consensus layout rules.
    envelope*: InitializationByteLimit
    program*: ProgramByteLimit
    jumps*: JumpCountLimit
    pages*: PageLimit
  InitializationCode* = object ## Explicit single-entry decode cache; caller owns its bounded sequential worker lifetime.
    source: Program
    bytes: ProgramByteLimit
    jumps: JumpCountLimit
  InitializationError* {.pure.} = enum ## No failed/default result contains a machine, memory or partially decoded input.
    Uninitialized, None, InvalidEnvelope, ArgumentsTooLarge, LimitExceeded, InvalidProgram
  InitializationHeap* = object ## Half-open heap page interval, reserving the stack in major zones.
    first*, past*: PageIndex
  InitializationResult* = object ## Private discriminated storage publishes only completely initialized executable snapshots.
    case status: InitializationError
    of None:
      # The resulting machine retains its program and memory children without back-references.
      completed: Machine
      heap: InitializationHeap
    else:
      # Rejection carries only its reason, never partially allocated state.
      discard

func error*(r: InitializationResult): InitializationError =
  ## Inspect success without permitting result retagging.
  r.status

func value*(r: InitializationResult): Machine {.inline, requires: r.status ==
    InitializationError.None.} =
  ## Borrowing the result yields a retained immutable machine only on successful selection.
  r.completed

func heapBounds*(r: InitializationResult): InitializationHeap {.inline,
    requires: r.status == InitializationError.None.} =
  ## The exact decoded layout is available only after successful standard initialization.
  r.heap

func fixed(input: openArray[byte], start, width: int): uint64 =
  ## Decode a fixed little-endian field after its caller establishes the complete header extent.
  result = 0
  # Widths here are at most four; shifts cannot overflow the 64-bit accumulator.
  for i in 0..<width:
    result = result or (uint64(input[start + i]) shl (8 * i))

func rounded(value, quantum: uint64): uint64 =
  ## Inputs are bounded by fixed-width envelope fields or the 2^24 argument bound, so rounding is safe.
  ((value + quantum - 1) div quantum) * quantum

func region(start, size: uint64, access: PageAccess, source: InitializationSource,
    offset, length: int): InitializationRegion =
  ## Convert the admitted page-aligned layout to exclusive page endpoints.
  InitializationRegion(first: PageIndex(uint32(start div 4096)),
    past: PageIndex(uint32((start+size) div 4096)), access: access, source: source,
    offset: offset, length: length)

proc initializeMachine*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits,
        retained: var InitializationCode): InitializationResult =
  ## Initialize the fixed program image after its metadata prefix has been decoded.
  ## Gas is caller supplied and initially uncharged. All size/policy checks precede page allocation.
  ## Resource refusals from program decoding, page capture or CPU snapshot allocation
  ## return `InitializationError.LimitExceeded`.
  # Argument admissibility is a protocol bound, separate from caller allocation policy.
  if uint64(arguments.len) > 0x1000000'u64:
    return InitializationResult(status: InitializationError.ArgumentsTooLarge)
  # The local envelope cap includes headers and all embedded data, not just instruction bytes.
  if uint64(input.len) > uint64(limits.envelope):
    return InitializationResult(status: InitializationError.LimitExceeded)
  # Eleven header bytes and a four-byte program length are mandatory even for empty sections.
  if input.len < 15:
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  let readOnlyLength = fixed(input, 0, 3)
  let writableLength = fixed(input, 3, 3)
  let extraPages = fixed(input, 6, 2)
  let stackLength = fixed(input, 8, 3)
  # Small fixed-width lengths make this sum safe; subtract before narrowing to an index.
  let dataLength = readOnlyLength + writableLength
  if dataLength > uint64(input.len - 15):
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  let codeOffset = 15 + int(dataLength)
  let codeLength = fixed(input, codeOffset - 4, 4)
  # Exact equality rejects both truncated code and trailing bytes; no alternate framing is accepted.
  if codeLength != uint64(input.len - codeOffset):
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  let roSize = rounded(readOnlyLength, 4096)
  let rwSize = rounded(writableLength, 4096) + extraPages * 4096
  let stackSize = rounded(stackLength, 4096)
  let argumentSize = rounded(uint64(arguments.len), 4096)
  # Retain the normative zone-separation check even though today's fixed-width fields bound it tightly.
  if 5 * 65536'u64 + rounded(readOnlyLength, 65536) +
      rounded(writableLength + extraPages * 4096, 65536) +
      rounded(stackLength, 65536) + 0x1000000'u64 > 0x100000000'u64:
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  let pageCount = (roSize + rwSize + stackSize + argumentSize) div 4096
  # Check the complete allocation, including zero pages, before program admission.
  if pageCount > uint64(uint32(limits.pages)):
    return InitializationResult(status: InitializationError.LimitExceeded)
  let reuse = uint64(retained.bytes) == uint64(limits.program) and
      uint64(retained.jumps) == uint64(limits.jumps) and isJamProgram(retained.source) and
      matchesProgramEncoding(retained.source, input.toOpenArray(codeOffset, input.len - 1))
  var source = retained.source
  if reuse:
    # Prior admission proves the exact encoding under identical parse limits; entry remains invocation-specific.
    if instructionOpcode(source, entry).error != ProgramError.None:
      return InitializationResult(status: InitializationError.InvalidProgram)
  else:
    let decoded = decodeJamProgram(input.toOpenArray(codeOffset, input.len - 1), entry,
        limits.program, limits.jumps)
    if decoded.error in {ProgramError.LimitExceeded, ProgramError.AllocationRefused}:
      return InitializationResult(status: InitializationError.LimitExceeded)
    if decoded.error != ProgramError.None:
      return InitializationResult(status: InitializationError.InvalidProgram)
    source = decoded.value # Replace the one retained source only after complete successful admission.
    retained = InitializationCode(source: source, bytes: limits.program, jumps: limits.jumps)
  # Capture each region directly, including read-only tails and the untouched stack and heap.
  let regions = [
    region(65536, roSize, PageAccess.ReadOnly, InitializationSource.First, 11,
      int(readOnlyLength)),
    region(131072 + rounded(readOnlyLength, 65536), rwSize, PageAccess.ReadWrite,
      InitializationSource.First, 11 + int(readOnlyLength), int(writableLength)),
    region(0xfefe0000'u64 - stackSize, stackSize, PageAccess.ReadWrite,
      InitializationSource.First, 0, 0),
    region(0xfeff0000'u64, argumentSize, PageAccess.ReadOnly, InitializationSource.Second,
      0, arguments.len)]
  let memory = captureInitializationMemory(regions, input, arguments, limits.pages)
  if memory.error in {MachineError.LimitExceeded, MachineError.AllocationRefused}:
    return InitializationResult(status: InitializationError.LimitExceeded)
  if memory.error != MachineError.None:
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(0xfefe0000'u64)
  registers[7] = RegisterValue(0xfeff0000'u64)
  registers[8] = RegisterValue(uint64(arguments.len))
  let captured = captureMachine(source, memory.value, MachineInfo(pc: entry, gas: gas,
    blockCharged: false, registers: registers))
  if captured.error == MachineError.LimitExceeded:
    return InitializationResult(status: InitializationError.LimitExceeded)
  if captured.error != MachineError.None:
    return InitializationResult(status: InitializationError.InvalidProgram)
  let heap = InitializationHeap(
    first: PageIndex(uint32((131072+rounded(readOnlyLength, 65536)) div 4096)),
    past: PageIndex(uint32((0xfefd0000'u64-rounded(stackLength, 65536)) div 4096)))
  InitializationResult(status: InitializationError.None, completed: captured.value, heap: heap)

proc initializeMachine*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits): InitializationResult =
  ## Initialize one immutable machine with a call-scoped decode cache.
  ## Resource refusals return `InitializationError.LimitExceeded`.
  var retained = default(InitializationCode)
  initializeMachine(input, arguments, entry, gas, limits, retained)

proc initializeJamProgram*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits,
    retained: var InitializationCode): InitializationResult =
  ## Standard Y admits one complete metadata-prefixed JAM blob. Metadata is opaque and ignored.
  if uint64(input.len) > uint64(limits.envelope):
    return InitializationResult(status: InitializationError.LimitExceeded)
  let metadata = decodeBytesBorrowed(input, ByteLimit(uint64(input.len)))
  if metadata.error != ContainerError.None or metadata.consumed == input.len:
    return InitializationResult(status: InitializationError.InvalidEnvelope)
  initializeMachine(input.toOpenArray(metadata.consumed, input.high), arguments,
    entry, gas, limits, retained)

proc initializeJamProgram*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits): InitializationResult =
  ## One-shot standard initialization retains no worker cache.
  var retained = default(InitializationCode)
  initializeJamProgram(input, arguments, entry, gas, limits, retained)
