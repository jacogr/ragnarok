## GP 0.8.0 T(state), chapters 6/7/8/9/11 and Safrole key/entropy definitions.
## This serializes state values; it does not execute Safrole or establish key validity.
import ./[natural, bounded, assurances, state_layout, state_trie]

type
  ## One fixed entropy word; the four-word state preserves accumulator/history order.
  StateEntropyWord* = distinct array[32, byte]
  ## Accumulator, then the three most recently ended epochs, with no count prefix.
  StateEntropy* = array[4, StateEntropyWord]
  ## The most recent block's timeslot is exactly E4 in state.
  StateTime* = distinct uint32
  ## Opaque state key encodings have separate nominal cryptographic roles.
  StateBsKey* = distinct array[32, byte]
  ## An Ed25519 state key is not an entropy word or Bandersnatch key.
  StateEdKey* = distinct array[32, byte]
  ## The full BLS public-key encoding has 144 bytes, including all zero bytes.
  StateBlsKey* = distinct array[144, byte]
  ## Validator metadata is opaque, fixed-width data rather than a string.
  StateValidatorMetadata* = distinct array[128, byte]
  ## All 336 bytes are copied values, preserving the protocol's field order.
  StateValidator* = object
    bandersnatch*: StateBsKey
    ed25519*: StateEdKey
    bls*: StateBlsKey
    metadata*: StateValidatorMetadata
  ## Only these three independent top-level chapters contain a bare variable validator roster.
  ValidatorChapter* {.pure.} = enum
    Staging = 7, Active = 8, Previous = 9
  ## Roster extraction uses an explicit ordinal, not a byte offset or service identifier.
  StateValidatorIndex* = distinct uint64
  ## Core count establishes the protocol population bound; other ceilings are caller resource policy.
  ValidatorStateConfig* = object
    cores*: CoreCount
    validators*: ElementLimit
    maxBytes*: ByteLimit
  ## Failed/default results never expose values, owners or consumed progress.
  StateComponentError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  ## Select success before accessing a complete fixed value or immutable snapshot.
  StateComponentResult*[T] = object
    case error*: StateComponentError
    of StateComponentError.None:
      value*: T # Successful alternatives alone carry application data.
    else:
      discard   # Failures contain only their reason.
  ## Prefix decoding publishes progress only after a whole component is valid.
  StateComponentRead*[T] = object
    value*: T
    consumed*: int
  ## Private acyclic ARC storage owns copied records; callers cannot mutate the referenced object.
  ValidatorStateData = ref object
    records: seq[StateValidator]
  ## Value handles share private immutable storage; replacing one handle cannot alter another snapshot.
  ValidatorStateSnapshot* = object
    data: ValidatorStateData

## Copy fixed protocol fields from an already validated byte extent.
proc fixed[N: static int](input: openArray[byte], offset: int): array[N, byte] =
  # Every caller has checked the complete component before entering this loop.
  for i in 0..<N: result[i] = input[offset+i]

## Copy a complete fixed field into a privately allocated entry payload.
proc put(input: openArray[byte], output: var seq[byte], cursor: var int) =
  # Allocation and total extent were established before the first write.
  for b in input:
    output[cursor] = b
    inc cursor

## Emit chapter 6's exact 128-byte value, retaining no source reference.
proc entropyEntry*(value: StateEntropy): StateEntry =
  result = StateEntry(key: chapterKey(StateChapter(6)), value: newSeq[byte](128))
  var cursor = 0
  # Preserve accumulator followed by historical entropy order; no dynamic length is serialized.
  for word in value: put(array[32, byte](word), result.value, cursor)

## Decode one complete entropy prefix into independent fixed copies; suffix bytes stay with the caller.
proc decodeStateEntropy*(input: openArray[byte]): StateComponentResult[StateComponentRead[
    StateEntropy]] =
  if input.len < 128:
    return StateComponentResult[StateComponentRead[StateEntropy]](
        error: StateComponentError.Truncated) # No partial history escapes.
  var value: StateEntropy
  # Each word's position is semantically significant, including all-zero historical words.
  for i in 0..<4: value[i] = StateEntropyWord(fixed[32](input, i*32))
  StateComponentResult[StateComponentRead[StateEntropy]](error: StateComponentError.None,
    value: StateComponentRead[StateEntropy](value: value, consumed: 128))

## Emit chapter 11's exact E4 value with no natural-number or tuple length prefix.
proc timeEntry*(value: StateTime): StateEntry =
  result = StateEntry(key: chapterKey(StateChapter(11)), value: newSeq[byte](4))
  # Explicit little-endian extraction avoids native alignment/endian assumptions.
  for i in 0..<4: result.value[i] = byte((uint32(value) shr (8*i)) and 255)

## Decode one E4 timeslot prefix without applying state-transition or chronology rules.
proc decodeStateTime*(input: openArray[byte]): StateComponentResult[StateComponentRead[StateTime]] =
  if input.len < 4:
    return StateComponentResult[StateComponentRead[StateTime]](
        error: StateComponentError.Truncated) # No partial numeric value is published.
  var value = 0'u32
  # Each source byte occupies a fixed little-endian position.
  for i in 0..<4: value = value or (uint32(input[i]) shl (8*i))
  StateComponentResult[StateComponentRead[StateTime]](error: StateComponentError.None,
    value: StateComponentRead[StateTime](value: StateTime(value), consumed: 4))

## Validate population, resource and native extents before allocation or count conversion.
proc extent(count: uint64, prefix: int, config: ValidatorStateConfig): StateComponentResult[int] =
  if uint64(config.cores) < 2:
    return StateComponentResult[int](error: StateComponentError.InvalidConfig) # No allowed population exists below two cores.
  if count < 6 or count mod 3 != 0 or count div 3 > uint64(config.cores):
    return StateComponentResult[int](error: StateComponentError.InvalidCount) # GP permits exactly 3c for 2 <= c <= core count.
  if count > uint64(config.validators):
    return StateComponentResult[int](error: StateComponentError.LimitExceeded) # Policy can be stricter than protocol cardinality.
  if count > uint64((high(int)-prefix) div 336) or count > uint64(high(int) div sizeof(
      StateValidator)):
    return StateComponentResult[int](error: StateComponentError.LengthOverflow) # Bound wire and typed storage before multiplication.
  let bytes = prefix+int(count)*336
  if uint64(bytes) > uint64(config.maxBytes):
    return StateComponentResult[int](error: StateComponentError.LimitExceeded) # Byte policy includes the canonical count prefix.
  StateComponentResult[int](error: StateComponentError.None, value: bytes)

## Serialize an ordered borrowed roster into a new chapter entry; null/repeated key records remain structural values.
proc validatorEntry*(chapter: ValidatorChapter, values: openArray[StateValidator],
                     config: ValidatorStateConfig): StateComponentResult[StateEntry] =
  let prefix = natural.encode(JamNatural(values.len))
  let checked = extent(uint64(values.len), prefix.len, config)
  if checked.error != StateComponentError.None:
    return StateComponentResult[StateEntry](error: checked.error) # Reject before payload allocation or any write.
  var entry = StateEntry(key: chapterKey(StateChapter(ord(chapter))), value: newSeq[byte](checked.value))
  var cursor = 0
  put(prefix.bytes.toOpenArray(0, prefix.len-1), entry.value, cursor)
  # Validator order defines ordinal identity; never sort or deduplicate this sequence.
  for validator in values:
    put(array[32, byte](validator.bandersnatch), entry.value, cursor)
    put(array[32, byte](validator.ed25519), entry.value, cursor)
    put(array[144, byte](validator.bls), entry.value, cursor)
    put(array[128, byte](validator.metadata), entry.value, cursor)
  StateComponentResult[StateEntry](error: StateComponentError.None, value: entry)

## Decode a canonical variable roster prefix into private immutable copied storage.
proc decodeStateValidators*(input: openArray[byte],
    config: ValidatorStateConfig): StateComponentResult[StateComponentRead[
    ValidatorStateSnapshot]] =
  if uint64(config.cores) < 2:
    return StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](
        error: StateComponentError.InvalidConfig) # Invalid policy never starts parsing.
  let count = natural.decode(input)
  if not count.ok:
    # Missing bytes and complete overlong forms remain distinct failure-only alternatives.
    if count.error == DecodeError.truncated:
      return StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](
        error: StateComponentError.Truncated) # No partial population is available yet.
    else:
      return StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](
        error: StateComponentError.NonCanonical) # A second encoding cannot identify the same population.
  let checked = extent(uint64(count.value), count.consumed, config)
  if checked.error != StateComponentError.None:
    return StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](
        error: checked.error) # Untrusted counts cannot trigger allocation yet.
  if input.len < checked.value:
    return StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](
        error: StateComponentError.Truncated) # Complete wire extent precedes snapshot allocation.
  let owner = ValidatorStateSnapshot(data: ValidatorStateData(records: newSeq[StateValidator](int(
      uint64(count.value)))))
  var cursor = int(count.consumed)
  # Each owned record copies all fields, including opaque BLS and metadata bytes.
  for i in 0..<owner.data.records.len:
    owner.data.records[i] = StateValidator(bandersnatch: StateBsKey(fixed[32](input, cursor)),
      ed25519: StateEdKey(fixed[32](input, cursor+32)), bls: StateBlsKey(fixed[144](input,
          cursor+64)),
      metadata: StateValidatorMetadata(fixed[128](input, cursor+208)))
    cursor += 336
  StateComponentResult[StateComponentRead[ValidatorStateSnapshot]](error: StateComponentError.None,
    value: StateComponentRead[ValidatorStateSnapshot](value: owner, consumed: cursor))

## Inspect a retained snapshot's population without exporting its mutable backing sequence.
proc validatorCount*(owner: ValidatorStateSnapshot): StateComponentResult[int] =
  if owner.data.isNil:
    return StateComponentResult[int](error: StateComponentError.InvalidOwner) # Default handles carry no population.
  StateComponentResult[int](error: StateComponentError.None, value: owner.data.records.len)

## Extract an independent fixed validator copy bound to its original immutable snapshot.
proc validatorAt*(owner: ValidatorStateSnapshot, index: StateValidatorIndex): StateComponentResult[
    StateValidator] =
  if owner.data.isNil:
    return StateComponentResult[StateValidator](error: StateComponentError.InvalidOwner) # Never dereference absent owners.
  if uint64(index) >= uint64(owner.data.records.len):
    return StateComponentResult[StateValidator](error: StateComponentError.InvalidIndex) # Check before narrowing to native indexing.
  StateComponentResult[StateValidator](error: StateComponentError.None, value: owner.data.records[
      int(uint64(index))])
