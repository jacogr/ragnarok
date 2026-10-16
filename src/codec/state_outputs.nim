## GP 0.8.0 T chapter 16 and recent_history lastaccoutspec: ordered last accumulation outputs.
## This codec preserves supplied sequence order; accumulation and output-log commitment derivation are separate.
import ./[natural, bounded, composite, state_layout, state_trie]
export ServiceIndex

type
  ## A service's accumulation output commitment is distinct from a state/trie root of equal width.
  OutputCommitment* = distinct array[32, byte]
  ## One complete fixed value pairs an E4 service identifier with its opaque 32-byte commitment.
  AccumulationOutput* = object
    service*: ServiceIndex
    commitment*: OutputCommitment
  ## Sequence extraction uses an ordinal, not a service ID or byte count.
  OutputLogIndex* = distinct uint64
  ## Caller resource policy bounds element work/storage and the complete count-prefixed payload.
  OutputLogConfig* = object
    items*: ElementLimit
    maxBytes*: ByteLimit
  ## Default/failed alternatives expose only reasons, never values, owners or partial progress.
  OutputLogError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  ## Only selected complete success contains an application payload.
  OutputLogResult*[T] = object
    case error*: OutputLogError
    of OutputLogError.None:
      value*: T # Success must be selected before application fields are read.
    else:
      discard   # Failure cannot fabricate an empty sequence or default commitment.
  ## Private acyclic ARC storage contains independent fixed pairs and no borrowed caller memory.
  OutputLogData = ref object
    values: seq[AccumulationOutput]
  ## Copied value handles retain immutable storage; replacing one handle leaves other copies unchanged.
  OutputLogSnapshot* = object
    data: OutputLogData
  ## Prefix success binds its complete captured sequence to the exact consumed byte extent.
  OutputLogRead* = object
    snapshot*: OutputLogSnapshot
    consumed*: int

## Bound announced counts, native wire/storage extents and whole-parent policy before access/allocation.
proc extent(count: uint64, prefix: int, config: OutputLogConfig): OutputLogResult[int] =
  if count > uint64(config.items):
    return OutputLogResult[int](error: OutputLogError.LimitExceeded) # Caller item policy precedes native extent checks.
  if count > uint64((high(int)-prefix) div 36) or count > uint64(high(int) div sizeof(
      AccumulationOutput)):
    return OutputLogResult[int](error: OutputLogError.LengthOverflow) # Both encoded pairs and retained typed records must fit.
  let bytes = prefix+int(count)*36
  if uint64(bytes) > uint64(config.maxBytes):
    return OutputLogResult[int](error: OutputLogError.LimitExceeded) # Even empty sequences consume their canonical count byte.
  OutputLogResult[int](error: OutputLogError.None, value: bytes)

## Decode a complete ordered sequence prefix after full count/extent preflight, without sorting or deduplication.
proc decodeOutputLog*(input: openArray[byte], config: OutputLogConfig): OutputLogResult[
    OutputLogRead] =
  let count = natural.decode(input)
  if not count.ok:
    if count.error == DecodeError.truncated:
      return OutputLogResult[OutputLogRead](error: OutputLogError.Truncated) # Missing count is not a valid empty log.
    else:
      return OutputLogResult[OutputLogRead](error: OutputLogError.NonCanonical) # Alternate complete count encodings reject.
  let checked = extent(uint64(count.value), count.consumed, config)
  if checked.error != OutputLogError.None:
    return OutputLogResult[OutputLogRead](error: checked.error) # No allocation or payload reads under invalid resource policy.
  if input.len < checked.value:
    return OutputLogResult[OutputLogRead](error: OutputLogError.Truncated) # The final pair must be present before capturing any earlier pair.
  let data = OutputLogData(values: newSeq[AccumulationOutput](int(uint64(count.value))))
  var cursor = int(count.consumed)
  # All service IDs and commitment bytes are fixed copies; their input positions never escape.
  for i in 0..<data.values.len:
    var service = 0'u32
    for j in 0..<4: service = service or (uint32(input[cursor+j]) shl (
        j*8)) # Explicit E4 little-endian service decoding.
    var commitment: array[32, byte]
    for j in 0..<32: commitment[j] = input[cursor+4+j] # Opaque fixed commitment has no own length prefix.
    data.values[i] = AccumulationOutput(service: ServiceIndex(service),
        commitment: OutputCommitment(commitment))
    cursor += 36
  OutputLogResult[OutputLogRead](error: OutputLogError.None,
    value: OutputLogRead(snapshot: OutputLogSnapshot(data: data), consumed: checked.value))

## Encode stable ordered source pairs into fresh C(16) bytes after complete extent preflight.
proc outputLogEntry*(values: openArray[AccumulationOutput],
    config: OutputLogConfig): OutputLogResult[StateEntry] =
  let count = natural.encode(JamNatural(values.len))
  let checked = extent(uint64(values.len), count.len, config)
  if checked.error != OutputLogError.None:
    return OutputLogResult[StateEntry](error: checked.error) # No output allocation before complete size/policy validation.
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
  OutputLogResult[StateEntry](error: OutputLogError.None, value: entry)

## Return copied sequence cardinality without exposing the private mutable array representation.
proc outputLogCount*(owner: OutputLogSnapshot): OutputLogResult[int] =
  if owner.data.isNil:
    return OutputLogResult[int](error: OutputLogError.InvalidOwner) # Default handles differ from captured zero-length logs.
  OutputLogResult[int](error: OutputLogError.None, value: owner.data.values.len)

## Extract one independent fixed pair through its retained owner and nominal sequence ordinal.
proc outputLogAt*(owner: OutputLogSnapshot, index: OutputLogIndex): OutputLogResult[
    AccumulationOutput] =
  if owner.data.isNil:
    return OutputLogResult[AccumulationOutput](error: OutputLogError.InvalidOwner) # Missing storage cannot return a fabricated service/commitment.
  if uint64(index) >= uint64(owner.data.values.len):
    return OutputLogResult[AccumulationOutput](error: OutputLogError.InvalidIndex) # Prove native narrowing and array access first.
  OutputLogResult[AccumulationOutput](error: OutputLogError.None, value: owner.data.values[int(
      uint64(index))])
