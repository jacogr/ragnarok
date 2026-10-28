# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded standalone JamV1 PolkaVM containers; see spec/pvm-artifacts.md.
## Decoding copies symbols and data into immutable program/memory owners. File loading is explicit; no application host ABI is inferred.
import std/syncio
import ../codec/natural
import ./[program, machine]

type
  ArtifactError* {.pure.} = enum ## Failed/default results contain only a typed reason.
    Uninitialized, None, InvalidFormat, UnsupportedVersion, LimitExceeded, InvalidProgram,
      InvalidMemory, MissingExport, IoError
  ArtifactResult*[T] = object ## Private discriminators prevent forged success and partial publication.
    case status: ArtifactError
    of None: completed: T
    else: discard
  ArtifactLimits* = object ## Explicit finite ceilings apply before allocation of guest-controlled storage.
    bytes*, codeBytes*: uint64
    symbols*, pages*: uint32
  ArtifactExport = object ## Private copied symbol/address pairs retain their validated program owner.
    name: string
    address: CodeAddress
  Artifact* = object ## Immutable captured program, initial memory and private copied symbol catalogs.
    initialized: bool
    source: Program
    memory: Memory
    imports: seq[string]
    exports: seq[ArtifactExport]
  Cursor = object ## Borrow-free parser state: integer extents and first-error status only.
    offset, finish: int
    error: ArtifactError

func error*[T](answer: ArtifactResult[T]): ArtifactError =
  ## Inspection never grants access to an unsuccessful payload.
  answer.status
func value*[T](answer: ArtifactResult[T]): T {.requires: answer.status == ArtifactError.None.} =
  ## Only a successful result publishes its complete owned value.
  answer.completed
func defaultArtifactLimits*(): ArtifactLimits =
  ## Convenience policy admits ordinary artifacts while bounding copied symbols and materialized pages.
  ArtifactLimits(bytes: 16777216, codeBytes: 4194304, symbols: 1024, pages: 8192)
func valid*(artifact: Artifact): bool =
  ## Default handles never grant execution or memory authority.
  artifact.initialized
func programOf*(artifact: Artifact): Program {.requires: artifact.initialized.} =
  ## Programs are immutable owners and safe to share with prepared engines.
  artifact.source
func memoryOf*(artifact: Artifact): Memory {.requires: artifact.initialized.} =
  ## Initial memory remains immutable even when an execution produces successor pages.
  artifact.memory
proc importSymbols*(artifact: Artifact): seq[string] {.requires: artifact.initialized.} =
  ## Copy the catalog; callers cannot replace retained symbol identities.
  result = newSeq[string](artifact.imports.len)
  for i, name in artifact.imports:
    result[i] = name # Strings have value semantics and retain no writable borrowed view.
proc entry*(artifact: Artifact, name: string): ArtifactResult[CodeAddress] =
  ## Required named lookup distinguishes invalid handles and absent exports from address zero.
  if not artifact.initialized:
    return ArtifactResult[CodeAddress](status: ArtifactError.Uninitialized)
  for exported in artifact.exports:
    if exported.name == name:
      return ArtifactResult[CodeAddress](status: ArtifactError.None, completed: exported.address)
  ArtifactResult[CodeAddress](status: ArtifactError.MissingExport)

proc number(input: openArray[byte], cursor: var Cursor): uint32 =
  ## Reuse canonical JAM prefix integers, restricted to the container's u32 domain.
  result = 0
  if cursor.error != ArtifactError.None: return
  if cursor.offset >= cursor.finish:
    cursor.error = ArtifactError.InvalidFormat
    return
  let decoded = decode(input.toOpenArray(cursor.offset, cursor.finish-1))
  if not decoded.ok:
    cursor.error = ArtifactError.InvalidFormat
    return
  if decoded.consumed > 5 or uint64(decoded.value) > uint64(high(uint32)):
    cursor.error = ArtifactError.InvalidFormat
    return
  cursor.offset += decoded.consumed
  result = uint32(uint64(decoded.value))

proc little(input: openArray[byte], start, count: int): uint64 =
  ## Callers establish the complete fixed-width extent before this bytewise little-endian read.
  result = 0
  for i in 0..<count:
    result = result or (uint64(input[start+i]) shl (i*8))

proc symbol(input: openArray[byte], cursor: var Cursor, count: int): string =
  ## A checked copied byte string supports opaque symbols without guessing UTF-8 validity.
  result = ""
  if cursor.error != ArtifactError.None: return
  if count < 0 or count > cursor.finish-cursor.offset:
    cursor.error = ArtifactError.InvalidFormat
    return
  result = newString(count)
  for i in 0..<count:
    result[i] = char(input[cursor.offset+i]) # No caller-owned address survives the decode.
  cursor.offset += count

proc initialMemory(ro, rw, stack: uint32, roData, rwData: seq[byte],
    limit: uint32): ArtifactResult[Memory] =
  ## Derive the pinned ABI with widened arithmetic; prove overlap and counts before materialization.
  let roPages = (uint64(ro)+4095) div 4096
  let rwPages = (uint64(rw)+4095) div 4096
  let stackPages = (uint64(stack)+4095) div 4096
  let rwStart = 131072'u64 + ((uint64(ro)+65535) div 65536)*65536
  let lowerEnd = rwStart + ((uint64(rw)+65535) div 65536)*65536 + 65536
  let stackSpace = ((uint64(stack)+65535) div 65536)*65536
  if stackSpace > 0xfffe0000'u64 or lowerEnd > 0xfffe0000'u64-stackSpace:
    return ArtifactResult[Memory](status: ArtifactError.InvalidMemory)
  if uint64(roData.len) > uint64(ro) or uint64(rwData.len) > uint64(rw):
    return ArtifactResult[Memory](status: ArtifactError.InvalidMemory)
  let count = roPages+rwPages+stackPages
  if count > uint64(limit): return ArtifactResult[Memory](status: ArtifactError.LimitExceeded)
  var pages = newSeq[PageImage](int(count))
  var slot = 0
  for region in 0..2:
    # Sorted nonoverlapping RO, RW and stack regions leave all guard pages inaccessible.
    let base = if region == 0: 65536'u64 elif region ==
        1: rwStart else: 0xfffe0000'u64-stackPages*4096
    let length = if region == 0: roPages elif region == 1: rwPages else: stackPages
    for page in 0..<int(length):
      var image = PageImage(index: PageIndex(uint32(base div 4096+uint64(page))),
          access: (if region == 0: PageAccess.ReadOnly else: PageAccess.ReadWrite))
      for within in 0..<4096:
        let offset = page*4096+within
        if region == 0 and offset < roData.len:
          image.bytes[within] = roData[offset] # Missing initialized bytes remain zero.
        elif region == 1 and offset < rwData.len:
          image.bytes[within] = rwData[offset] # Stack is entirely zero-initialized.
      pages[slot] = image
      inc slot
  let memory = captureMemory(pages, PageLimit(limit))
  if memory.error != MachineError.None:
    return ArtifactResult[Memory](status: ArtifactError.InvalidMemory)
  ArtifactResult[Memory](status: ArtifactError.None, completed: memory.value)

proc decodeArtifact*(input: openArray[byte], limits: ArtifactLimits =
    defaultArtifactLimits()): ArtifactResult[Artifact] =
  ## Admit one complete documented JamV1 container; every refusal discards all partial owners.
  template refuse(reason: ArtifactError): untyped =
    return ArtifactResult[Artifact](status: reason)
  if uint64(input.len) > limits.bytes: refuse(ArtifactError.LimitExceeded)
  if input.len < 14: refuse(ArtifactError.InvalidFormat)
  if input[0] != byte('P') or input[1] != byte('V') or input[2] != byte('M') or input[3] != 0:
    refuse(ArtifactError.InvalidFormat)
  if input[4] != 3: refuse(ArtifactError.UnsupportedVersion)
  if little(input, 5, 8) != uint64(input.len): refuse(ArtifactError.InvalidFormat)
  var cursor = Cursor(offset: 13, finish: input.len, error: ArtifactError.None)
  var ro, rw, stack: uint32 = 0
  var roData, rwData, wire: seq[byte] = @[]
  var imports: seq[string] = @[]
  var exports: seq[ArtifactExport] = @[]
  var previous = 0
  var ended, optional = false
  while cursor.offset < cursor.finish:
    # Mandatory low-bit sections are unique and ascending; optional sections carry only bounded extents.
    let section = int(input[cursor.offset])
    inc cursor.offset
    if section == 0:
      ended = true
      break
    if section < 128:
      if optional or section > 6 or section <= previous: refuse(ArtifactError.InvalidFormat)
      previous = section
    else:
      optional = true # No mandatory section may follow the optional metadata tail.
    let length = number(input, cursor)
    if cursor.error != ArtifactError.None: refuse(cursor.error)
    if uint64(length) > uint64(cursor.finish-cursor.offset): refuse(ArtifactError.InvalidFormat)
    let start = cursor.offset
    let finish = start+int(length)
    var part = Cursor(offset: start, finish: finish, error: ArtifactError.None)
    case section
    of 1:
      ro = number(input, part)
      rw = number(input, part)
      stack = number(input, part)
    of 2, 3, 6:
      # The outer byte limit bounds data copies; code has a separate decoder ceiling.
      if section == 6 and uint64(length) > limits.codeBytes: refuse(ArtifactError.LimitExceeded)
      var bytes = newSeq[byte](int(length))
      for i in 0..<int(length): bytes[i] = input[start+i]
      if section == 2: roData = bytes
      elif section == 3: rwData = bytes
      else: wire = bytes
      part.offset = finish
    of 4:
      let count = number(input, part)
      if part.error != ArtifactError.None: refuse(part.error)
      if count > limits.symbols or count > 1024: refuse(ArtifactError.LimitExceeded)
      if uint64(count)*4 > uint64(finish-part.offset): refuse(ArtifactError.InvalidFormat)
      let offsets = part.offset
      let symbols = offsets+int(count)*4
      let size = finish-symbols
      for i in 0..<int(count):
        # Validate every offset pair, including the first prefix and final symbol endpoint.
        let first = little(input, offsets+i*4, 4)
        let last = if i+1 < int(count): little(input, offsets+(i+1)*4, 4) else: uint64(size)
        if first > last or last > uint64(size) or (i == 0 and first != 0):
          refuse(ArtifactError.InvalidFormat)
        var name = Cursor(offset: symbols+int(first), finish: symbols+int(last),
            error: ArtifactError.None)
        imports.add(symbol(input, name, int(last-first)))
      if count == 0 and size != 0: refuse(ArtifactError.InvalidFormat)
      part.offset = finish
    of 5:
      let count = number(input, part)
      if part.error != ArtifactError.None: refuse(part.error)
      if count > limits.symbols or count > 1024: refuse(ArtifactError.LimitExceeded)
      if uint64(count)*2 > uint64(finish-part.offset): refuse(ArtifactError.InvalidFormat)
      for i in 0..<int(count):
        let pc = number(input, part)
        let size = number(input, part)
        if part.error != ArtifactError.None: refuse(part.error)
        let name = symbol(input, part, int(size))
        if part.error != ArtifactError.None: refuse(part.error)
        for old in exports:
          if old.name == name: refuse(ArtifactError.InvalidFormat)
        exports.add(ArtifactExport(name: name, address: CodeAddress(pc)))
    else:
      part.offset = finish # Unknown optional metadata is skipped without interpreting its contents.
    if part.error != ArtifactError.None: refuse(part.error)
    if part.offset != finish: refuse(ArtifactError.InvalidFormat)
    cursor.offset = finish
  if not ended or cursor.offset != cursor.finish: refuse(ArtifactError.InvalidFormat)
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(limits.codeBytes),
      JumpCountLimit(limits.codeBytes))
  if decoded.error != ProgramError.None: refuse(ArtifactError.InvalidProgram)
  for exported in exports:
    if instructionOpcode(decoded.value, exported.address).error != ProgramError.None:
      refuse(ArtifactError.InvalidProgram)
  let memory = initialMemory(ro, rw, stack, roData, rwData, limits.pages)
  if memory.error != ArtifactError.None: refuse(memory.error)
  ArtifactResult[Artifact](status: ArtifactError.None, completed: Artifact(initialized: true,
      source: decoded.value, memory: memory.value, imports: imports, exports: exports))

proc initialMachine*(artifact: Artifact, name: string, gas: MachineGas): ArtifactResult[Machine] =
  ## Create one independent ABI entry state; imported hosts remain the caller's explicit responsibility.
  let selected = artifact.entry(name)
  if selected.error != ArtifactError.None:
    return ArtifactResult[Machine](status: selected.error)
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(0xfffe0000'u64)
  let captured = captureMachine(artifact.source, artifact.memory, MachineInfo(pc: selected.value,
      gas: gas, registers: registers))
  if captured.error != MachineError.None:
    return ArtifactResult[Machine](status: ArtifactError.InvalidProgram)
  ArtifactResult[Machine](status: ArtifactError.None, completed: captured.value)

proc loadArtifact*(path: string, limits: ArtifactLimits = defaultArtifactLimits()): ArtifactResult[Artifact] =
  ## A bounded chunk reader checks the live stream, including growth after open; file cleanup is unconditional.
  var file: File = nil
  if not open(file, path, fmRead):
    return ArtifactResult[Artifact](status: ArtifactError.IoError)
  defer: close(file)
  var bytes: seq[byte] = @[]
  var chunk = default(array[4096, byte])
  while true:
    let count = readBuffer(file, addr chunk[0], chunk.len)
    if count == 0:
      if failed(file): return ArtifactResult[Artifact](status: ArtifactError.IoError)
      break # Only clean EOF finishes the single exact artifact snapshot.
    if count < 0: return ArtifactResult[Artifact](status: ArtifactError.IoError)
    if uint64(bytes.len) > limits.bytes or uint64(count) > limits.bytes-uint64(bytes.len):
      return ArtifactResult[Artifact](status: ArtifactError.LimitExceeded)
    for i in 0..<count:
      bytes.add(chunk[i]) # At most one policy-bounded container is retained.
  decodeArtifact(bytes, limits)

