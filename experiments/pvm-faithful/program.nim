# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JamV1 ProgramParts/ProgramBlob admission translated from pinned common/program.rs.
## Sections retain slices of one immutable input owner. Optional-section ordering, canonical
## varints, length checks and legacy bitmask padding follow the source, including acceptance
## of trailing bytes after EOF when the whole-blob length metadata still matches. Other ISAs
## are explicitly unsupported by this experiment, rather than interpreted as JamV1.

import std/[assertions, bitops]
import ./shared_bytes
export shared_bytes

type
  BlobError* {.pure.} = enum
    ## Default/failed results expose only a reason; successful payloads require a checked accessor.
    InvalidInput, UnsupportedIsa, InvalidVarint, InvalidSection, InvalidCode, Ok
  ProgramParts* = object
    ## Source section views and declared virtual lengths; each view retains its own source lifetime.
    roSize*, rwSize*, stackSize*: uint32
    ro*, rw*, encodedCode*, importOffsets*, importSymbols*, exports*: SharedBytes
    debugStrings*, debugPrograms*, debugRanges*, metadata*: SharedBytes
  ProgramBlob* = object
    ## Admitted sections plus validated raw code, jump table width and exact bitmask bytes.
    parts*: ProgramParts
    code*, mask*, jumpTable*: SharedBytes
    jumpWidth*: byte

type
  BlobResult* = object
    ## A failed discriminator has no program payload, and successful payload extraction is guarded.
    case success: bool
    of true: admitted: ProgramBlob
    of false: failure: BlobError
  Reader = object
    ## Mutable cursor containing a borrowed byte view; the cursor itself is an ordinary object.
    ## A view marker here would pass cursor metadata by value and lose position/error updates.
    data: openArray[byte]
    position: int
    error: BlobError

proc ok*(answer: BlobResult): bool {.inline.} =
  ## Success is explicit; default results cannot expose zero-initialized programs.
  answer.success

proc error*(answer: BlobResult): BlobError =
  ## Return the source admission category without exposing failed payload storage.
  if answer.success: BlobError.Ok else: answer.failure

proc blob*(answer: BlobResult): ProgramBlob =
  ## Copy immutable retained section handles only after proving successful admission.
  assert answer.ok
  answer.admitted

proc fail(reader: var Reader, error: BlobError) =
  ## Preserve the first parser error while later helpers stop consuming input.
  if reader.error == BlobError.Ok: reader.error = error

proc take(reader: var Reader, length: int): int =
  ## Prove the complete extent before advancing; failure never produces a readable interval.
  result = reader.position
  if reader.error != BlobError.Ok: return
  if length < 0 or length > reader.data.len-reader.position:
    reader.fail(BlobError.InvalidInput)
  else:
    reader.position += length

proc byteValue(reader: var Reader): byte =
  ## Source read_byte checks one byte before reading it.
  let at = reader.take(1)
  result = if reader.error == BlobError.Ok: reader.data[at] else: 0'u8

proc varint(reader: var Reader): uint32 =
  ## Match read_varint's leading-one width, little-endian tail and canonicality checks.
  result = 0
  let first = reader.byteValue()
  if reader.error != BlobError.Ok: return
  let length = leadingZeroBits(not first)
  if length > 4:
    reader.fail(BlobError.InvalidVarint)
    return
  let at = reader.take(length)
  if reader.error != BlobError.Ok: return
  var value = uint64(uint32(first) and (255'u32 shr length)) shl (length*8)
  for index in 0..<length:
    value = value or (uint64(reader.data[at+index]) shl (index*8))
  if (length != 0 and value < (1'u64 shl (7*length))) or value > uint64(high(uint32)):
    reader.fail(BlobError.InvalidVarint)
  else:
    result = uint32(value)

proc section(reader: var Reader, source: SharedBytes, current: var byte,
    expected: byte): SharedBytes =
  ## Missing optional/ordinary sections are empty; present sections retain their parent bytes.
  result = default(SharedBytes)
  if reader.error != BlobError.Ok or current != expected: return
  let length = int(reader.varint())
  let at = reader.take(length)
  if reader.error == BlobError.Ok:
    result = source.slice(at, length)
    current = reader.byteValue()

proc fromParts*(parts: ProgramParts): BlobResult =
  ## ProgramBlob::from_parts validates payload sizes and legacy code/jump/mask framing.
  if parts.ro.len > int(parts.roSize) or parts.rw.len > int(parts.rwSize):
    return BlobResult(success: false, failure: BlobError.InvalidInput)
  if parts.encodedCode.len == 0: return BlobResult(success: false, failure: BlobError.InvalidCode)
  var reader = Reader(data: parts.encodedCode.view(), error: BlobError.Ok)
  let entries = reader.varint()
  if entries > 16'u32*1024*1024: return BlobResult(success: false, failure: BlobError.InvalidCode)
  let width = reader.byteValue()
  let codeLength = reader.varint()
  if width > 4 or codeLength > 32'u32*1024*1024: return BlobResult(success: false,
      failure: BlobError.InvalidCode)
  # The source bounds above also prove multiplication cannot overflow u32.
  let jumpLength = int(entries)*int(width)
  let jumpAt = reader.take(jumpLength)
  let codeAt = reader.take(int(codeLength))
  if reader.error != BlobError.Ok: return BlobResult(success: false, failure: reader.error)
  let maskAt = reader.position
  let maskLength = parts.encodedCode.len-maskAt
  if maskLength != (int(codeLength)+7) div 8: return BlobResult(success: false,
      failure: BlobError.InvalidCode)
  if (codeLength and 7) != 0:
    let last = reader.data[reader.data.len-1]
    let forbidden = byte(255'u32 shl (codeLength and 7))
    if (last and forbidden) != 0: return BlobResult(success: false, failure: BlobError.InvalidCode)
  BlobResult(success: true, admitted: ProgramBlob(parts: parts, jumpWidth: width,
    jumpTable: parts.encodedCode.slice(jumpAt, jumpLength),
    code: parts.encodedCode.slice(codeAt, int(codeLength)),
    mask: parts.encodedCode.slice(maskAt, maskLength)))

proc parse*(source: SharedBytes): BlobResult =
  ## ProgramParts::from_bytes then ProgramBlob::from_parts, retaining all successful source slices.
  let bytes = source.view()
  if bytes.len < 14 or bytes[0] != 80 or bytes[1] != 86 or bytes[2] != 77 or bytes[3] != 0:
    return BlobResult(success: false, failure: BlobError.InvalidInput)
  if bytes[4] != 3: return BlobResult(success: false, failure: BlobError.UnsupportedIsa)
  var length = 0'u64
  for index in 0..<8: length = length or (uint64(bytes[5+index]) shl (index*8))
  if length != uint64(source.len): return BlobResult(success: false,
      failure: BlobError.InvalidInput)
  var reader = Reader(data: bytes, position: 13, error: BlobError.Ok)
  var parts = default(ProgramParts)
  var current = reader.byteValue()
  if current == 1:
    let size = int(reader.varint())
    let start = reader.position
    parts.roSize = reader.varint()
    parts.rwSize = reader.varint()
    parts.stackSize = reader.varint()
    if reader.position-start != size: reader.fail(BlobError.InvalidSection)
    current = reader.byteValue()
  parts.ro = reader.section(source, current, 2)
  parts.rw = reader.section(source, current, 3)
  if current == 4 and reader.error == BlobError.Ok:
    let size = int(reader.varint())
    let start = reader.position
    let count = reader.varint()
    if count > 1024: reader.fail(BlobError.InvalidSection)
    let offsetsLength = int(count)*4
    let offsetsAt = reader.take(offsetsLength)
    let consumed = reader.position-start
    if consumed > size: reader.fail(BlobError.InvalidSection)
    let symbolsLength = max(0, size-consumed)
    let symbolsAt = reader.take(symbolsLength)
    if reader.error == BlobError.Ok:
      parts.importOffsets = source.slice(offsetsAt, offsetsLength)
      parts.importSymbols = source.slice(symbolsAt, symbolsLength)
    current = reader.byteValue()
  parts.exports = reader.section(source, current, 5)
  parts.encodedCode = reader.section(source, current, 6)
  parts.debugStrings = reader.section(source, current, 128)
  parts.debugPrograms = reader.section(source, current, 129)
  parts.debugRanges = reader.section(source, current, 130)
  parts.metadata = reader.section(source, current, 131)
  while reader.error == BlobError.Ok and (current and 128) != 0:
    # Preserve upstream acceptance of unknown optional sections, including skipped duplicates.
    let size = int(reader.varint())
    discard reader.take(size)
    current = reader.byteValue()
  if reader.error != BlobError.Ok: return BlobResult(success: false, failure: reader.error)
  if current != 0: return BlobResult(success: false, failure: BlobError.InvalidSection)
  fromParts(parts)

proc findExport*(blob: ProgramBlob, name: string): tuple[found: bool, pc: uint32] =
  ## Public export iteration stops on the first malformed entry and returns the first name match.
  result = (false, 0'u32)
  if blob.parts.exports.len == 0: return
  var reader = Reader(data: blob.parts.exports.view(), error: BlobError.Ok)
  let count = reader.varint()
  for index in 0'u32..<count:
    let pc = reader.varint()
    let length = int(reader.varint())
    let at = reader.take(length)
    if reader.error != BlobError.Ok: return
    var matches = length == name.len
    if matches:
      for character in 0..<length:
        if reader.data[at+character] != byte(name[character]): matches = false
    if matches: return (true, pc)

proc findImport*(blob: ProgramBlob, name: string): tuple[found: bool, index: uint32] =
  ## Iterate source offset-delimited import names; malformed ranges stop lookup without guessing.
  result = (false, 0'u32)
  let offsets = blob.parts.importOffsets.view()
  let symbols = blob.parts.importSymbols.view()
  let count = offsets.len div 4
  for index in 0..<count:
    var first = 0'u32
    var finish = uint32(symbols.len)
    for byteIndex in 0..<4:
      first = first or (uint32(offsets[index*4+byteIndex]) shl (byteIndex*8))
    if index+1 < count:
      finish = 0
      for byteIndex in 0..<4:
        finish = finish or (uint32(offsets[(index+1)*4+byteIndex]) shl (byteIndex*8))
    if first > finish or uint64(finish) > uint64(symbols.len): return
    var matches = uint64(finish-first) == uint64(name.len)
    if matches:
      for character in 0..<name.len:
        if symbols[int(first)+character] != byte(name[character]): matches = false
    if matches: return (true, uint32(index))
