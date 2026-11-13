# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded standalone JamV1 PolkaVM containers; see spec/pvm-artifacts.md.
## Section bytes are borrowed until capture into immutable program/memory owners; symbols are copied.
## File loading is explicit; no application host ABI is inferred.

import std/syncio
when defined(linux) or defined(macosx):
  import std/posix/posix
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
  SectionSpan = object ## Validated input extents stay local; no borrowed address is retained.
    first, past: int

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

proc initialMemory(ro, rw, stack: uint32, input: openArray[byte], roData, rwData: SectionSpan,
    limit: uint32): ArtifactResult[Memory] =
  ## Derive the pinned ABI with widened arithmetic; prove overlap and counts before materialization.
  let roLength = roData.past-roData.first
  let rwLength = rwData.past-rwData.first
  let roPages = (uint64(ro)+4095) div 4096
  let rwPages = (uint64(rw)+4095) div 4096
  let stackPages = (uint64(stack)+4095) div 4096
  let rwStart = 131072'u64 + ((uint64(ro)+65535) div 65536)*65536
  let lowerEnd = rwStart + ((uint64(rw)+65535) div 65536)*65536 + 65536
  let stackSpace = ((uint64(stack)+65535) div 65536)*65536
  if stackSpace > 0xfffe0000'u64 or lowerEnd > 0xfffe0000'u64-stackSpace:
    return ArtifactResult[Memory](status: ArtifactError.InvalidMemory)
  if uint64(roLength) > uint64(ro) or uint64(rwLength) > uint64(rw):
    return ArtifactResult[Memory](status: ArtifactError.InvalidMemory)
  let count = roPages+rwPages+stackPages
  if count > uint64(limit): return ArtifactResult[Memory](status: ArtifactError.LimitExceeded)
  # Checked section offsets select independent prefixes in the same call-scoped borrowed container.
  let regions = [
    InitializationRegion(first: PageIndex(16), past: PageIndex(uint32(16+roPages)),
      access: PageAccess.ReadOnly, source: InitializationSource.First, offset: roData.first,
      length: roLength),
    InitializationRegion(first: PageIndex(uint32(rwStart div 4096)),
      past: PageIndex(uint32(rwStart div 4096+rwPages)), access: PageAccess.ReadWrite,
      source: InitializationSource.Second, offset: rwData.first, length: rwLength),
    InitializationRegion(first: PageIndex(uint32(0xfffe0000'u64 div 4096-stackPages)),
      past: PageIndex(uint32(0xfffe0000'u64 div 4096)), access: PageAccess.ReadWrite,
      source: InitializationSource.First, offset: 0, length: 0)]
  let memory = captureInitializationMemory(regions, input, input, PageLimit(limit))
  if memory.error in {MachineError.LimitExceeded, MachineError.AllocationRefused}:
    return ArtifactResult[Memory](status: ArtifactError.LimitExceeded)
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
  var roData, rwData, wire = SectionSpan(first: 0, past: 0)
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
      # Keep only admitted extents; final owners copy these bytes after complete container framing.
      if section == 6 and uint64(length) > limits.codeBytes: refuse(ArtifactError.LimitExceeded)
      let span = SectionSpan(first: start, past: finish)
      if section == 2: roData = span
      elif section == 3: rwData = span
      else: wire = span
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
  # Absent/empty wire yields an empty view and the same decoder refusal; successful bytes are owned.
  let decoded = decodeJamProgram(input.toOpenArray(wire.first, wire.past-1), CodeAddress(0),
      ProgramByteLimit(limits.codeBytes), JumpCountLimit(limits.codeBytes))
  if decoded.error == ProgramError.AllocationRefused: refuse(ArtifactError.LimitExceeded)
  if decoded.error != ProgramError.None: refuse(ArtifactError.InvalidProgram)
  for exported in exports:
    if instructionOpcode(decoded.value, exported.address).error != ProgramError.None:
      refuse(ArtifactError.InvalidProgram)
  let memory = initialMemory(ro, rw, stack, input, roData, rwData, limits.pages)
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
  ## Size regular files from the open descriptor and read directly into their owned buffer.
  ## The live stream decides the final extent, with bounded chunk reads for growth or unknown sizes.
  if path.len == 0 or path.len > 4096:
    return ArtifactResult[Artifact](status: ArtifactError.IoError)
  for character in path:
    if character == char(0): return ArtifactResult[Artifact](
        status: ArtifactError.IoError) # Native strings must preserve exact path identity.
  var file: File = nil
  if not open(file, path, fmRead):
    return ArtifactResult[Artifact](status: ArtifactError.IoError)
  defer: close(file)
  let maximum = min(limits.bytes, uint64(MaxContainerLen))
  var bytes: seq[byte] = @[]
  when defined(linux) or defined(macosx):
    var metadata = default(Stat)
    if posix.fstat(getFileHandle(file), metadata) == 0 and S_ISREG(metadata.st_mode) and
        metadata.st_size >= 0:
      # The descriptor ties size to this open file even if its pathname is replaced.
      let size = uint64(metadata.st_size)
      if size > maximum: return ArtifactResult[Artifact](status: ArtifactError.LimitExceeded)
      bytes = newSeqUninit[byte](int(size))
      if uint64(bytes.len) != size:
        return ArtifactResult[Artifact](status: ArtifactError.LimitExceeded)
      var filled = 0
      while filled < bytes.len:
        # Each read fills only its owned tail. A clean early EOF discards uninitialized bytes.
        let requested = bytes.len-filled
        let count = readBuffer(file, addr bytes[filled], requested)
        if count < 0 or count > requested or failed(file):
          return ArtifactResult[Artifact](status: ArtifactError.IoError)
        if count == 0:
          bytes.setLen(filled)
          return decodeArtifact(bytes, limits)
        filled += count
  var chunk = default(array[4096, byte])
  while true:
    # Read one byte past the remaining allowance to distinguish exact EOF from excess input.
    let remaining = maximum-uint64(bytes.len)
    let requested = int(min(remaining, uint64(chunk.len-1)))+1
    let count = readBuffer(file, addr chunk[0], requested)
    if count == 0:
      if failed(file): return ArtifactResult[Artifact](status: ArtifactError.IoError)
      break # Only clean EOF finishes the single exact artifact snapshot.
    if count < 0 or count > requested or failed(file):
      return ArtifactResult[Artifact](status: ArtifactError.IoError)
    if uint64(count) > remaining:
      return ArtifactResult[Artifact](status: ArtifactError.LimitExceeded)
    let first = bytes.len
    let past = first+count
    # The chunk already holds every byte. Check growth before taking a pointer into the new span.
    bytes.growUnsafe(past)
    if bytes.len != past: return ArtifactResult[Artifact](status: ArtifactError.LimitExceeded)
    copyMem(addr bytes[first], addr chunk[0], count)
  decodeArtifact(bytes, limits)

