## Isolated default/failed component value, owner, copied record and progress reads require success contracts.
import std/[assertions, cmdline, syncio]
import ../../src/codec/[state_safrole, state_trie, bounded, assurances, natural]
let useDefault = paramStr(2) == "default"
let policy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
    maxBytes: ByteLimit(2017))
let broad = ValidatorStateConfig(cores: CoreCount(high(uint64)), validators: ElementLimit(high(
    uint64)), maxBytes: ByteLimit(high(uint64)))
let strict = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(5),
    maxBytes: ByteLimit(2017))
let invalidConfig = ValidatorStateConfig(cores: CoreCount(1), validators: ElementLimit(6),
    maxBytes: ByteLimit(2017))
let encoded = validatorEntry(ValidatorChapter.Active, newSeq[StateValidator](6), policy)
assert encoded.error == StateComponentError.None
let decoded = decodeStateValidators(encoded.value.value, policy)
assert decoded.error == StateComponentError.None
let owner = decoded.value.value
let huge = natural.encode(JamNatural(high(uint64)))
case paramStr(1)
of "entropy-value":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      StateEntropy]]) else: decodeStateEntropy([])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo array[32, byte](parsed.value.value[0])[0]
of "entropy-consumed":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      StateEntropy]]) else: decodeStateEntropy([])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.consumed
of "time-value":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      StateTime]]) else: decodeStateTime([])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo uint32(parsed.value.value)
of "time-consumed":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      StateTime]]) else: decodeStateTime([])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.consumed
of "entry":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateEntry]) else: validatorEntry(
      ValidatorChapter.Active, newSeq[StateValidator](5), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value.value.len
of "snapshot":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo validatorCount(parsed.value.value).value
of "snapshot-consumed":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.consumed
of "prefix":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[int]) else: stateValidatorPrefixSize([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value
of "size":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[int]) else: stateValidatorSize(
      ValidatorCount(0), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value
of "count":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[int]) else: validatorCount(default(ValidatorStateSnapshot))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo parsed.value
of "item":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateValidator]) else: validatorAt(
      default(ValidatorStateSnapshot), StateValidatorIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo array[32, byte](parsed.value.bandersnatch)[0]
of "index":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateValidator]) else: validatorAt(owner,
      StateValidatorIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidIndex)
  echo array[32, byte](parsed.value.bandersnatch)[0]
of "size-overflow":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[int]) else: stateValidatorSize(
      ValidatorCount(high(uint64)), broad)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LengthOverflow)
  echo parsed.value
of "decode-overflow":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators(huge.bytes.toOpenArray(0, huge.len-1), broad)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LengthOverflow)
  echo parsed.value.consumed
of "decode-config":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([], invalidConfig)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidConfig)
  echo parsed.value.consumed
of "decode-count":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([0'u8], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value.consumed
of "decode-policy":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([6'u8], strict)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LimitExceeded)
  echo parsed.value.consumed
of "decode-noncanonical":
  # No default/failed result may authorize this value, owner or progress observation.
  let parsed = if useDefault: default(StateComponentResult[StateComponentRead[
      ValidatorStateSnapshot]]) else: decodeStateValidators([128'u8, 6], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.NonCanonical)
  echo parsed.value.consumed
of "entry-tag":
  # An invalid enum representation cannot authorize a roster entry in another chapter namespace.
  let ordinal = if useDefault: 0 else: 10
  let parsed = if useDefault: default(StateComponentResult[StateEntry]) else:
    validatorEntry(ValidatorChapter(ordinal), newSeq[StateValidator](6), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidTag)
  echo parsed.value.value.len
of "direct-time":
  # Preserve the original direct-time default-result probe alongside actual fixed-prefix result types.
  let parsed = default(StateComponentResult[StateTime])
  echo uint32(parsed.value)
else:
  # Unknown selectors must fail as harness errors, never as successful rejection evidence.
  quit(2)
