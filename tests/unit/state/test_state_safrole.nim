# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplementary immutable snapshot, fixed-copy and default/failure guard contracts.
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/codec/[state_safrole, bounded, assurances]

## Verify source destruction and extracted-copy mutation cannot change retained validator records.
proc main() =
  let config = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(2017))
  var source = newSeq[StateValidator](6)
  var field = default(array[32, byte])
  field[0] = 17
  source[0].bandersnatch = StateBsKey(field)
  let encoded = validatorEntry(ValidatorChapter.Active, source, config)
  assert encoded.error == StateComponentError.None
  assert array[31, byte](encoded.value.key)[0] == 8
  var wire = encoded.value.value
  let decoded = decodeStateValidators(wire, config)
  assert decoded.error == StateComponentError.None
  let retained = decoded.value.value
  # Destroy both original wire and typed source after snapshot creation.
  for i in 0..<wire.len: wire[i] = 0
  source[0] = default(StateValidator)
  let item = validatorAt(retained, StateValidatorIndex(0))
  assert item.error == StateComponentError.None
  assert array[32, byte](item.value.bandersnatch)[0] == 17
  var copy = item.value
  copy.bandersnatch = StateBsKey(default(array[32, byte]))
  assert array[32, byte](validatorAt(retained, StateValidatorIndex(0)).value.bandersnatch)[0] == 17
  assert validatorCount(retained).value == 6
  # Default/failed payload reads are checked in isolated processes by the trial runner.

  var replaced = retained
  replaced = default(ValidatorStateSnapshot)
  assert validatorCount(retained).value == 6
  let absent = validatorCount(replaced)
  assert absent.error == StateComponentError.InvalidOwner

  assert validatorAt(replaced, StateValidatorIndex(0)).error == StateComponentError.InvalidOwner
  let missing = validatorAt(retained, StateValidatorIndex(high(uint64)))
  assert missing.error == StateComponentError.InvalidIndex

  let rejected = validatorEntry(ValidatorChapter.Staging, source.toOpenArray(0, 4), config)
  assert rejected.error == StateComponentError.InvalidCount

  let short = decodeStateValidators(@[6'u8], config)
  assert short.error == StateComponentError.Truncated

  let time = timeEntry(StateTime(high(uint32)))
  assert time.value == @[255'u8, 255, 255, 255]
  assert uint32(decodeStateTime(time.value).value.value) == high(uint32)
  # Exercise every underlying chapter octet because Nimony integer-to-enum conversion is unchecked.
  for ordinal in 0..255:
    let candidate = validatorEntry(ValidatorChapter(ordinal), source, config)
    if ordinal >= 7 and ordinal <= 9:
      # Each allowed chapter retains its own exact state-key namespace.
      assert candidate.error == StateComponentError.None
      assert int(array[31, byte](candidate.value.key)[0]) == ordinal
    else:
      # Other enum representations cannot silently serialize another state chapter.
      assert candidate.error == StateComponentError.InvalidTag
  echo "PASS state components: immutable snapshots, fixed copies, nil/index and result guards"

main()

# Produce an escaped immutable roster whose typed input, entry and wire aliases all retire in the callee.
proc escaped(marker: byte): ValidatorStateSnapshot =
  var source = newSeq[StateValidator](6)
  var field = default(array[32, byte])
  field[0] = marker
  source[0].bandersnatch = StateBsKey(field)
  source[0].ed25519 = StateEdKey(field)
  let policy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(2017))
  let encoded = validatorEntry(ValidatorChapter.Active, source, policy)
  assert encoded.error == StateComponentError.None
  let decoded = decodeStateValidators(encoded.value.value, policy)
  assert decoded.error == StateComponentError.None
  result = decoded.value.value
  source[0] = default(StateValidator)

# Retain independent aliases through replacement and copy mutation, then release every success/error path.
proc cycle() =
  let policy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(2017))
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert array[32, byte](validatorAt(alias, StateValidatorIndex(0)).value.bandersnatch)[0] == 17
  assert array[32, byte](validatorAt(owner, StateValidatorIndex(0)).value.bandersnatch)[0] == 29
  var record = validatorAt(alias, StateValidatorIndex(0)).value
  record.bandersnatch = StateBsKey(default(array[32, byte]))
  record.ed25519 = StateEdKey(default(array[32, byte]))
  record.bls = StateBlsKey(default(array[144, byte]))
  record.metadata = StateValidatorMetadata(default(array[128, byte]))
  assert array[32, byte](validatorAt(alias, StateValidatorIndex(0)).value.ed25519)[0] == 17
  owner = default(ValidatorStateSnapshot)
  assert validatorCount(owner).error == StateComponentError.InvalidOwner
  assert validatorCount(alias).value == 6
  assert validatorAt(alias, StateValidatorIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  assert decodeStateValidators([6'u8], policy).error == StateComponentError.Truncated
  assert decodeStateValidators([128'u8, 6], policy).error == StateComponentError.NonCanonical
  assert stateValidatorSize(ValidatorCount(7), policy).error == StateComponentError.InvalidCount
  var entropy = default(StateEntropy)
  var bytes = default(array[32, byte])
  bytes[0] = 45
  entropy[0] = StateEntropyWord(bytes)
  let encodedEntropy = entropyEntry(entropy)
  let decodedEntropy = decodeStateEntropy(encodedEntropy.value)
  assert decodedEntropy.error == StateComponentError.None
  var copied = decodedEntropy.value.value
  copied[0] = StateEntropyWord(default(array[32, byte]))
  assert array[32, byte](decodedEntropy.value.value[0])[0] == 45
  assert decodeStateEntropy([]).error == StateComponentError.Truncated
  assert decodeStateTime([]).error == StateComponentError.Truncated

let broad = ValidatorStateConfig(cores: CoreCount(high(uint64)), validators: ElementLimit(high(uint64)),
  maxBytes: ByteLimit(high(uint64)))
# The largest natural has valid divisibility but cannot fit a native wire or typed allocation extent.
assert stateValidatorSize(ValidatorCount(high(uint64)), broad).error ==
    StateComponentError.LengthOverflow
let tinyPolicy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
    maxBytes: ByteLimit(2017))
assert stateValidatorSize(ValidatorCount(6), tinyPolicy).value == 2017
# A complete scan has the same exact size and error precedence as the allocating decoder.
let valid = validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6), tinyPolicy)
assert valid.error == StateComponentError.None
assert stateValidatorPrefixSize(valid.value.value, tinyPolicy).value == 2017
# Warmup excludes allocator initialization from the isolated release comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Each scope drops both replaced and retained owners, copied entries, fixed values and rejected temporaries.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_safrole", 1000, beforeRelease, afterRelease)
echo "STATE_SAFROLE_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony state components: escaped/replaced owners, copied fields, arithmetic and scoped ARC release passed"
