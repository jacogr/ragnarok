# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published shuffle permutations plus rotation, posterior offender, resizing and owner boundaries.
import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/guarantors
import ../../../src/codec/[state_safrole, assurances, bounded, header, guarantees, work_report, disputes]
import ../../support/arc_evidence

## The existing test observer refuses hash calls while retaining the maintained production backend otherwise.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## A tiny profile has three four-slot rotations; the validator ceiling also permits resize tests.
proc config(): GuarantorConfig =
  GuarantorConfig(roster: ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
    maxBytes: ByteLimit(10000)), epochSlots: EpochSlots(12), rotationSlots: GuarantorRotationSlots(4),
    offenders: ElementLimit(9))

## Capture full independently identifiable records; input changes cannot alter the codec-owned snapshot.
proc roster(count, offset: int, policy: ValidatorStateConfig): ValidatorStateSnapshot =
  var records = newSeq[StateValidator](count)
  for i in 0..<count:
    var key = default(array[32, byte])
    key[0] = byte((i+offset) mod 256)
    var bls = default(array[144, byte])
    var metadata = default(array[128, byte])
    bls[0] = 7
    metadata[0] = 8
    records[i] = StateValidator(ed25519: StateEdKey(key), bandersnatch: StateBsKey(key),
      bls: StateBlsKey(bls), metadata: StateValidatorMetadata(metadata))
  let entry = validatorEntry(ValidatorChapter.Active, records, policy).value
  decodeStateValidators(entry.value, policy).value.value

## Assert all eight original permutations, including the empty case and draws across hash-group boundaries.
proc official() {.raises.} =
  for row in readFile(getEnv("RAGNAROK_GUARANTORS")).splitLines:
    if row.len == 0: continue # Only the trailing file newline is omitted.
    let fields = row.splitWhitespace
    let count = parseInt(fields[0])
    var bytes = default(array[32, byte])
    for i in 0..<32:
      assert parseHex(fields[1][i*2..i*2+1], bytes[i]) == 2 # Complete original entropy bytes.
    let shuffled = shuffleValidatorIndices(ValidatorCount(count), StateEntropyWord(bytes),
        ElementLimit(1023))
    assert shuffled.error == GuarantorError.None
    if count > 0:
      let expected = fields[2].split(',')
      assert expected.len == count
      for i in 0..<count:
        assert int(shuffled.value.shuffledIndex(StateValidatorIndex(i)).value) == parseInt(expected[i])
    else:
      assert fields[2] == "-" # The original zero-count vector produces no elements.
    assert shuffled.value.shuffledIndex(StateValidatorIndex(count)).error ==
        GuarantorError.InvalidIndex

## Verify core multiplicity, rotation direction/reset, previous-epoch entropy and different roster sizes.
proc boundaries() =
  let policy = config()
  let active = roster(9, 1, policy.roster)
  let previous = roster(6, 21, policy.roster)
  var entropy = default(StateEntropy)
  var historical = default(array[32, byte])
  historical[0] = 99
  entropy[3] = StateEntropyWord(historical)
  let initial = planGuarantors(active, previous, entropy, StateTime(0), [], policy).value
  let rotated = planGuarantors(active, previous, entropy, StateTime(4), [], policy).value
  var counts = default(array[3, int])
  for i in 0..<9:
    let first = initial.guarantorAt(GuaranteeSlot(0), GuarantorIndex(i)).value
    inc counts[int(uint64(first.core))]
    let next = rotated.guarantorAt(GuaranteeSlot(4), GuarantorIndex(i)).value
    assert uint64(next.core) == (uint64(first.core)+1) mod 3
    let prior = rotated.guarantorAt(GuaranteeSlot(0), GuarantorIndex(i)).value
    assert uint64(prior.core) == uint64(first.core) # The lower bound is included.
  assert counts == [3, 3, 3]
  let crossed = planGuarantors(active, previous, entropy, StateTime(12), [], policy).value
  var oldEntropy = entropy
  oldEntropy[2] = entropy[3]
  let old = planGuarantors(previous, previous, oldEntropy, StateTime(8), [], policy).value
  for i in 0..<6:
    let actual = crossed.guarantorAt(GuaranteeSlot(8), GuarantorIndex(i)).value
    let expected = old.guarantorAt(GuaranteeSlot(8), GuarantorIndex(i)).value
    assert uint64(actual.core) == uint64(expected.core)
    assert array[32, byte](actual.validator.ed25519)[0] == byte(21+i)
  assert crossed.guarantorAt(GuaranteeSlot(8), GuarantorIndex(6)).error ==
      GuarantorError.InvalidIndex
  assert crossed.guarantorAt(GuaranteeSlot(7), GuarantorIndex(0)).error ==
      GuarantorError.InvalidSlot
  assert crossed.guarantorAt(GuaranteeSlot(13), GuarantorIndex(0)).error ==
      GuarantorError.InvalidSlot
  assert initial.guarantorAt(GuaranteeSlot(1), GuarantorIndex(0)).error ==
      GuarantorError.InvalidSlot
  for i in 0..<9:
    let reset = crossed.guarantorAt(GuaranteeSlot(12), GuarantorIndex(i)).value
    let first = initial.guarantorAt(GuaranteeSlot(0), GuarantorIndex(i)).value
    assert uint64(reset.core) == uint64(first.core) # Epoch resets rotation without changing entropy[2].
  var bad = default(array[32, byte])
  bad[0] = 1
  var offenders = @[OffenderKey(bad)]
  let filtered = planGuarantors(active, previous, entropy, StateTime(4), offenders, policy).value
  offenders[0] = default(OffenderKey) # Mutating borrowed offender input cannot alter the retained plan.
  let nulled = filtered.guarantorAt(GuaranteeSlot(4), GuarantorIndex(0)).value
  assert array[32, byte](nulled.validator.ed25519) == default(array[32, byte])
  assert array[32, byte](nulled.validator.bandersnatch) == default(array[32, byte])
  assert array[144, byte](nulled.validator.bls) == default(array[144, byte])
  assert array[128, byte](nulled.validator.metadata) == default(array[128, byte])
  let priorNull = filtered.guarantorAt(GuaranteeSlot(0), GuarantorIndex(0)).value
  assert array[32, byte](priorNull.validator.ed25519) == default(array[32, byte])
  let unaffected = filtered.guarantorAt(GuaranteeSlot(4), GuarantorIndex(1)).value
  assert array[32, byte](unaffected.validator.ed25519)[0] == 2
  assert planGuarantors(active, previous, entropy, StateTime(4), [OffenderKey(bad), OffenderKey(
      bad)], policy).error == GuarantorError.NonCanonical
  var invalid = policy
  invalid.rotationSlots = GuarantorRotationSlots(0)
  assert planGuarantors(active, previous, entropy, StateTime(4), [], invalid).error ==
      GuarantorError.InvalidConfig
  invalid.rotationSlots = GuarantorRotationSlots(5)
  assert planGuarantors(active, previous, entropy, StateTime(4), [], invalid).error ==
      GuarantorError.InvalidConfig
  assert planGuarantors(default(ValidatorStateSnapshot), previous, entropy, StateTime(4), [],
      policy).error == GuarantorError.InvalidState
  assert default(GuarantorPlan).guarantorAt(GuaranteeSlot(0), GuarantorIndex(0)).error ==
      GuarantorError.Uninitialized
  assert default(GuarantorPermutation).shuffledIndex(StateValidatorIndex(0)).error ==
      GuarantorError.Uninitialized
  assert shuffleValidatorIndices(ValidatorCount(1024), entropy[0], ElementLimit(1023)).error ==
      GuarantorError.LimitExceeded
  var large = policy
  large.roster.cores = CoreCount(341)
  large.roster.validators = ElementLimit(1023)
  large.roster.maxBytes = ByteLimit(400000)
  large.epochSlots = EpochSlots(600)
  large.rotationSlots = GuarantorRotationSlots(10)
  let full = roster(1023, 1, large.roster)
  let nearEnd = planGuarantors(full, previous, entropy, StateTime(high(uint32)), [], large).value
  var fullCounts = default(array[341, int])
  for i in 0..<1023:
    let assigned = nearEnd.guarantorAt(GuaranteeSlot(high(uint32)), GuarantorIndex(i)).value
    inc fullCounts[int(uint64(assigned.core))] # Maximum E4 slot and full population stay bounded.
  for count in fullCounts:
    assert count == 3 # No validator is lost or assigned to an inactive core.
  var tight = policy
  tight.roster.maxBytes = ByteLimit(1)
  assert planGuarantors(active, previous, entropy, StateTime(4), [], tight).error ==
      GuarantorError.InvalidConfig
  tight = policy
  tight.offenders = ElementLimit(0)
  assert planGuarantors(active, previous, entropy, StateTime(4), [OffenderKey(bad)], tight).error ==
      GuarantorError.LimitExceeded
  failHash(1)
  assert shuffleValidatorIndices(ValidatorCount(9), entropy[0], ElementLimit(1023)).error ==
      GuarantorError.BackendFailure
  assert planGuarantors(active, previous, entropy, StateTime(4), [], policy).error ==
      GuarantorError.BackendFailure
  failHash(0)

## A scoped plan must release both private tables and hash scratch on success/refusal without caller roots.
proc releaseCycle(refuse: bool) =
  let policy = config()
  let active = roster(9, 1, policy.roster)
  let previous = roster(6, 21, policy.roster)
  failHash(cint(if refuse: 1 else: 0))
  let plan = planGuarantors(active, previous, default(StateEntropy), StateTime(12), [], policy)
  assert plan.error == (if refuse: GuarantorError.BackendFailure else: GuarantorError.None)
  failHash(0)

## Fallible fixture I/O must fail the native process rather than silently skip published comparisons.
proc main() {.raises.} =
  official()
  boundaries()
  releaseCycle(false) # Warm backend/lowering paths before checking steady live allocations.
  let before = getOccupiedMem()
  for i in 0..<1000:
    releaseCycle(i mod 2 == 0) # Alternate complete release and provider-refused construction.
  let after = getOccupiedMem()
  assert after == before
  recordArcRelease("guarantor_assignments", 1000, before, after)
  echo "PASS guarantor assignments: eight published shuffles, rotations, epoch resize, offenders and ARC release"
try:
  main() # Propagate all assertion failures and unhandled fixture errors to Hastur.
except:
  quit(2) # No missing or malformed fixture can be mistaken for native success.
