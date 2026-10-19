# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standard GP 0.8.0 JAM envelope and memory initialization, followed by validated machine capture.
## Exposes InitializationLimits, InitializationError/Result and initializeMachine. Inputs are borrowed
## only during the call; successful machines own immutable acyclic copies. See spec/pvm-initialization.md.

import std/assertions
import ./[program, machine]

type
  InitializationByteLimit* = distinct uint64 ## Local input policy bounds the complete JAM envelope independently of the embedded program.
  InitializationLimits* = object ## Independent local allocation and decoding ceilings never change consensus layout rules.
    envelope*: InitializationByteLimit
    program*: ProgramByteLimit
    jumps*: JumpCountLimit
    pages*: PageLimit
  InitializationError* {.pure.} = enum ## No failed/default result contains a machine, memory or partially decoded input.
    Uninitialized, None, InvalidEnvelope, ArgumentsTooLarge, LimitExceeded, InvalidProgram
  InitializationResult* = object ## Private discriminated storage publishes only completely initialized executable snapshots.
    case status: InitializationError
    of None:
      # The resulting machine retains its program and memory children without back-references.
      completed: Machine
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

# Decode a fixed little-endian field after its caller establishes the complete header extent.
func fixed(input: openArray[byte], start, width: int): uint64 =
  result = 0
  # Widths here are at most four; shifts cannot overflow the 64-bit accumulator.
  for i in 0..<width:
    result = result or (uint64(input[start + i]) shl (8 * i))

# Inputs are bounded by fixed-width envelope fields or the 2^24 argument bound, so rounding is safe.
func rounded(value, quantum: uint64): uint64 =
  ((value + quantum - 1) div quantum) * quantum

# Materialize an already-budgeted region with explicit zero padding and copied input bytes.
proc region(pages: var seq[PageImage], start, size: uint64, access: PageAccess,
    input: openArray[byte], offset, length: int) =
  var consumed = 0
  # Regions are page-aligned, nonoverlapping and emitted in increasing address order.
  for ordinal in 0..<int(size div 4096):
    var page = PageImage(index: PageIndex(uint32(start div 4096) + uint32(ordinal)),
      access: access, bytes: default(array[4096, byte]))
    # Bytes outside the serialized extent remain explicitly zero, including complete extra heap pages.
    for i in 0..<4096:
      if consumed < length:
        # Bounds were validated before allocation; no byte is read from padding or another section.
        page.bytes[i] = input[offset + consumed]
        inc consumed
    pages.add(page)

proc initializeMachine*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits): InitializationResult =
  ## Apply standard Y framing/layout, validate the embedded program and entry, then capture a CPU.
  ## Gas is caller supplied and initially uncharged. All size/policy checks precede page allocation.
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
  # Check the complete allocation, including zero pages, before building any page image.
  if pageCount > uint64(uint32(limits.pages)):
    return InitializationResult(status: InitializationError.LimitExceeded)
  let decoded = decodeProgram(input.toOpenArray(codeOffset, input.len - 1), entry,
    limits.program, limits.jumps)
  # Program policy exhaustion is local; malformed code or an invalid entry is separately rejected.
  if decoded.error == ProgramError.LimitExceeded:
    return InitializationResult(status: InitializationError.LimitExceeded)
  elif decoded.error != ProgramError.None:
    # Standard Y itself does not validate code; this executable-machine adapter deliberately does.
    return InitializationResult(status: InitializationError.InvalidProgram)
  var pages = newSeqOfCap[PageImage](int(pageCount))
  region(pages, 65536, roSize, PageAccess.ReadOnly, input, 11, int(readOnlyLength))
  region(pages, 131072 + rounded(readOnlyLength, 65536), rwSize, PageAccess.ReadWrite,
    input, 11 + int(readOnlyLength), int(writableLength))
  region(pages, 0xfefe0000'u64 - stackSize, stackSize, PageAccess.ReadWrite, input, 0, 0)
  region(pages, 0xfeff0000'u64, argumentSize, PageAccess.ReadOnly, arguments, 0, arguments.len)
  let memory = captureMemory(pages, limits.pages)
  # These invariants were established above; a failure indicates an internal layout bug.
  assert memory.error == MachineError.None
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(0xfefe0000'u64)
  registers[7] = RegisterValue(0xfeff0000'u64)
  registers[8] = RegisterValue(uint64(arguments.len))
  let captured = captureMachine(decoded.value, memory.value, MachineInfo(pc: entry, gas: gas,
    blockCharged: false, registers: registers))
  assert captured.error == MachineError.None
  InitializationResult(status: InitializationError.None, completed: captured.value)
