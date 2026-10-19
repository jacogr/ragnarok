# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T chapter 16 and recent_history lastaccoutspec: ordered last accumulation outputs.
## This codec preserves supplied sequence order; accumulation and output-log commitment
## derivation are separate.
##
## Exposes output-log profiles and records, chapter-16 entry construction/decoding and ordered
## item access.

import std/assertions
import ./[natural, bounded, composite, state_layout, state_trie]
export ServiceIndex

type
  OutputCommitment* = distinct array[32, byte] ## A service's accumulation output commitment is distinct from a state/trie root of equal width.
  AccumulationOutput* = object ## One complete fixed value pairs an E4 service identifier with its opaque 32-byte commitment.
    service*: ServiceIndex
    commitment*: OutputCommitment
  OutputLogIndex* = distinct uint64 ## Sequence extraction uses an ordinal, not a service ID or byte count.
  OutputLogConfig* = object ## Caller resource policy bounds element work/storage and the complete count-prefixed payload.
    items*: ElementLimit
    maxBytes*: ByteLimit
  OutputLogError* {.pure.} = enum ## Default/failed alternatives expose only reasons, never values, owners or partial progress.
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  OutputLogResult*[T] = object ## Only selected complete success contains an application payload.
    case status: OutputLogError
    of None:
      completed: T             # Success must be selected before application fields are read.
    else:
      discard                  # Failure cannot fabricate an empty sequence or default commitment.
  ## Private acyclic ARC storage contains independent fixed pairs and no borrowed caller memory.
  OutputLogData = ref object
    values: seq[AccumulationOutput]
  OutputLogSnapshot* = object ## Copied value handles retain immutable storage; replacing one handle leaves other copies unchanged.
    data: nil OutputLogData
  OutputLogRead* = object ## Prefix success binds its complete captured sequence to the exact consumed byte extent.
    snapshot*: OutputLogSnapshot
    consumed*: int

func error*[T](value: OutputLogResult[T]): OutputLogError =
  ## Failure reasons are read-only and never authorize payload or progress access.
  value.status
func value*[T](value: OutputLogResult[T]): T
    {.inline, requires: value.status == OutputLogError.None.} =
  ## Complete public payloads and private extent proofs require successful selection.
  value.completed

## Bound announced counts, native wire/storage extents and whole-parent policy before access/allocation.
proc extent(count: uint64, prefix: int, config: OutputLogConfig): OutputLogResult[int] =
  if count > uint64(config.items):
    return OutputLogResult[int](status: OutputLogError.LimitExceeded) # Caller item policy precedes native extent checks.
  if count > uint64((high(int)-prefix) div 36) or count > uint64(high(int) div sizeof(
      AccumulationOutput)):
    return OutputLogResult[int](status: OutputLogError.LengthOverflow) # Both encoded pairs and retained typed records must fit.
  let bytes = prefix+int(count)*36
  if uint64(bytes) > uint64(config.maxBytes):
    return OutputLogResult[int](status: OutputLogError.LimitExceeded) # Even empty sequences consume their canonical count byte.
  OutputLogResult[int](status: OutputLogError.None, completed: bytes)

proc decodeOutputLog*(input: openArray[byte], config: OutputLogConfig): OutputLogResult[
    OutputLogRead] =
  ## Decode a complete ordered sequence prefix after full count/extent preflight, without sorting or deduplication.
  let count = natural.decode(input)
  if not count.ok:
    if count.error == DecodeError.truncated:
      return OutputLogResult[OutputLogRead](status: OutputLogError.Truncated) # Missing count is not a valid empty log.
    else:
      return OutputLogResult[OutputLogRead](status: OutputLogError.NonCanonical) # Alternate complete count encodings reject.
  let checked = extent(uint64(count.value), count.consumed, config)
  if checked.error != OutputLogError.None:
    return OutputLogResult[OutputLogRead](status: checked.error) # No allocation or payload reads under invalid resource policy.
  if input.len < checked.value:
    return OutputLogResult[OutputLogRead](status: OutputLogError.Truncated) # The final pair must be present before capturing any earlier pair.
  let data = OutputLogData(values: newSeq[AccumulationOutput](int(uint64(count.value))))
  var cursor = int(count.consumed)
  # All service IDs and commitment bytes are fixed copies; their input positions never escape.
  for i in 0..<data.values.len:
    var service = 0'u32
    for j in 0..<4: service = service or (uint32(input[cursor+j]) shl (
        j*8)) # Explicit E4 little-endian service decoding.
    var commitment = default(array[32, byte])
    for j in 0..<32: commitment[j] = input[cursor+4+j] # Opaque fixed commitment has no own length prefix.
    data.values[i] = AccumulationOutput(service: ServiceIndex(service),
        commitment: OutputCommitment(commitment))
    cursor += 36
  OutputLogResult[OutputLogRead](status: OutputLogError.None,
    completed: OutputLogRead(snapshot: OutputLogSnapshot(data: data), consumed: checked.value))

proc outputLogEntry*(values: openArray[AccumulationOutput],
    config: OutputLogConfig): OutputLogResult[StateEntry] =
  ## Encode stable ordered source pairs into fresh C(16) bytes after complete extent preflight.
  let count = natural.encode(JamNatural(values.len))
  let checked = extent(uint64(values.len), count.len, config)
  if checked.error != OutputLogError.None:
    return OutputLogResult[StateEntry](status: checked.error) # No output allocation before complete size/policy validation.
  var entry = StateEntry(key: chapterKey(StateChapter(16)), value: newSeq[byte](checked.value))
  for i in 0..<count.len: entry.value[i] = count.bytes[i] # Exactly one outer natural sequence count.
  var cursor = int(count.len)
  # Source sequence order is significant; this is not a canonical dictionary or set codec.
  for value in values:
    for j in 0..<4: entry.value[cursor+j] = byte((uint32(value.service) shr (j*8)) and
        255) # Services use E4, never ordinary naturals.
    let commitment = array[32, byte](value.commitment)
    for j in 0..<32: entry.value[cursor+4+j] = commitment[
        j] # Copy every fixed hash octet into independent output.
    cursor += 36
  OutputLogResult[StateEntry](status: OutputLogError.None, completed: entry)

proc outputLogCount*(owner: OutputLogSnapshot): OutputLogResult[int] =
  ## Return copied sequence cardinality without exposing the private mutable array representation.
  let data = owner.data
  if data == nil:
    return OutputLogResult[int](status: OutputLogError.InvalidOwner) # Default handles differ from captured zero-length logs.
  OutputLogResult[int](status: OutputLogError.None, completed: data.values.len)

proc outputLogAt*(owner: OutputLogSnapshot, index: OutputLogIndex): OutputLogResult[
    AccumulationOutput] =
  ## Extract one independent fixed pair through its retained owner and nominal sequence ordinal.
  let data = owner.data
  if data == nil:
    return OutputLogResult[AccumulationOutput](status: OutputLogError.InvalidOwner) # Missing storage cannot return a fabricated service/commitment.
  if uint64(index) >= uint64(data.values.len):
    return OutputLogResult[AccumulationOutput](status: OutputLogError.InvalidIndex) # Prove native narrowing and array access first.
  OutputLogResult[AccumulationOutput](status: OutputLogError.None, completed: data.values[int(
      uint64(index))])
