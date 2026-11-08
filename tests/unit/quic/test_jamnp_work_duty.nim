# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_work_duty_arc_release"}

## Actual source chapters bind GP core assignments to local identity/time; failures never expose duty authority.

import std/[assertions, syncio]
import ../../../src/jamnp-s/work_duty
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/state/[safrole, disputes as state_disputes, layout as state_layout,
    trie as state_trie]
from ../../../src/codec/work/report import CoreIndex
import ../../../src/chain/[parameters, presets]
import ../../../src/state/[store, guarantors]
import ../../support/arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## The existing observer refuses the real hash primitive without replacing assignment or protocol logic.

proc key(index: int): StateEdKey =
  ## Fixed distinct identities select actual original roster positions, not a test-provided success bit.
  var bytes = default(array[32, byte])
  bytes[0] = byte(index+10) # Avoid the reserved GP null-validator Ed encoding02 followed by zeros.
  StateEdKey(bytes)

proc parameters(cores = 3): Parameters =
  ## Actual Tiny epoch/rotation timing with an explicit configured core ceiling permits smaller active populations.
  var wire = presetParameters(ChainPreset.Tiny).value.encodeParameters
  wire[24] = byte(cores)
  wire[25] = 0
  decodeParameters(wire).value

proc limits(): WorkDutyLimits =
  ## Exact source copying and cumulative dispute work remain independently bounded.
  WorkDutyLimits(chapterBytes: ByteLimit(10000), disputeItems: ElementLimit(128))

proc state(current = 6, previous = 9, slot = 16'u32, offender = false): StateStoreSnapshot =
  ## Test-only source maps contain genuine canonical encodings for every chapter this projection requires; no adoption certificate is asserted.
  let roster = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
      maxBytes: ByteLimit(10000))
  var active = newSeq[StateValidator](current)
  var old = newSeq[StateValidator](previous)
  for index in 0..<active.len:
    # Distinct complete metadata catches accidental use of the previous roster or key-only reconstruction.
    var metadata = default(array[128, byte])
    metadata[0] = byte(index+1)
    metadata[127] = byte(index+111)
    active[index] = StateValidator(ed25519: key(index+1), metadata: StateValidatorMetadata(metadata))
  for index in 0..<old.len: old[index] = StateValidator(ed25519: key(index+101))
  let firstEncoded = validatorEntry(ValidatorChapter.Active, active, roster)
  assert firstEncoded.error == StateComponentError.None, "current roster " & $current & ": " &
      $firstEncoded.error
  let first = firstEncoded.value
  let secondEncoded = validatorEntry(ValidatorChapter.Previous, old, roster)
  assert secondEncoded.error == StateComponentError.None, "previous roster " & $previous & ": " &
      $secondEncoded.error
  let second = secondEncoded.value
  var disputes = default(DisputeState)
  if offender: disputes.offenders = @[OffenderKey(array[32, byte](key(2)))]
  let judgments = disputeStateEntry(disputes, DisputeStateConfig(perSet: ElementLimit(128),
    totalItems: ElementLimit(128), maxBytes: ByteLimit(10000))).value
  let built = newStateStore([first, second, judgments, entropyEntry(default(StateEntropy)),
      timeEntry(StateTime(slot))],
    StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(16), perValue: ByteLimit(10000),
      totalValueBytes: ByteLimit(50000), nodes: TrieNodeLimit(1000)),
      writes: ElementLimit(16), writeValueBytes: ByteLimit(50000)))
  assert built.error == StateStoreError.None, "duty state construction: " & $built.error
  built.value.snapshot.value

proc changed(source: StateStoreSnapshot, chapter: uint8, bytes: seq[byte],
    remove = false): StateStoreSnapshot =
  ## Replace/delete only one original chapter on a private test branch, keeping the parent immutable.
  var store = forkStateStore(source).value
  let write = StateWrite(key: chapterKey(StateChapter(chapter)),
    kind: (if remove: StateWriteKind.Delete else: StateWriteKind.Put), value: bytes)
  assert store.apply([write]).error == StateStoreError.None
  store.snapshot.value
let source = state()
let profile = parameters()
let cap = limits()
  # Independent hashlib BLAKE2b(seed||E4(group)) and shrinking-array shuffle yield [5,2,1,4,3,0].
  # At slot20, rotation2 modulo two active cores gives these exact original-validator assignments.
const SixAt20 = [1'u64, 0, 0, 1, 1, 0]
for index in 0..<6:
  let expected = SixAt20[index]
  let checked = captureWorkDuty(source, profile, workRecipient(key(index+1), StateTime(20)),
      CoreIndex(expected), cap)
  assert checked.error == WorkDutyError.None, "six-member duty index=" & $index & ", reason=" & $checked.error
  let duty = checked.value
  assert duty.valid and uint64(duty.core) == expected
  assert array[32, byte](duty.localIdentity) == array[32, byte](key(index+1))
  assert uint32(duty.sourceTime) == 16 and uint32(duty.observedTime) == 20
  assert duty.epochDuration == 12 and duty.rotationDuration == 4
  assert uint16(duty.validatorIndex) == uint16(index) # Credentials use the original roster position.
  assert uint64(duty.coreCapacity) == 3 # Configured capacity is not inferred from the six-member active population.
  assert duty.participantCount == 3
  var ordinal = 0
  for original in 0..<6:
    # The independent GP permutation selects the full cohort in original roster order, not shuffled order.
    if SixAt20[original] != expected: continue
    let participant = duty.participantAt(ordinal)
    assert participant.error == WorkDutyError.None
    assert uint16(participant.value.index) == uint16(original)
    let memberKey = array[32, byte](participant.value.validator.ed25519)
    let expectedKey = array[32, byte](key(original+1))
    assert memberKey == expectedKey
    let metadata = array[128, byte](participant.value.validator.metadata)
    assert metadata[0] == byte(original+1) and metadata[127] == byte(original+111)
    inc ordinal
  assert ordinal == 3
  assert duty.participantAt(-1).error == WorkDutyError.InvalidIndex
  assert duty.participantAt(3).error == WorkDutyError.InvalidIndex
  var detached = duty.participantAt(0).value
  detached.validator = nullValidator() # Mutating a copied record cannot alter a retained source-bound cohort.
  let retainedKey = array[32, byte](duty.participantAt(0).value.validator.ed25519)
  assert retainedKey != array[32, byte](detached.validator.ed25519)
  assert uint16(duty.shardCount) == 6 # Three configured cores do not imply nine actual validators.
  assert duty.activeAt(StateTime(20)) and duty.activeAt(StateTime(23))
  assert not duty.activeAt(StateTime(19)) and not duty.activeAt(StateTime(24))
  assert not default(WorkDuty).activeAt(StateTime(20))
  assert array[32, byte](duty.sourceRoot) == array[32, byte](source.commitment.root)
  assert captureWorkDuty(source, profile, workRecipient(key(index+1), StateTime(20)),
    CoreIndex(1-expected), cap).error == WorkDutyError.NotAssigned
  assert captureWorkDuty(source, profile, workRecipient(key(index+1), StateTime(20)),
    CoreIndex(2), cap).error == WorkDutyError.NotAssigned, "a configured but inactive core cannot acquire a guarantor"
# Rotation uses the observed slot, while a subsequent unknown epoch is refused before assumptions about new entropy or rosters.
assert captureWorkDuty(source, profile, workRecipient(key(2), StateTime(16)), CoreIndex(1),
    cap).error == WorkDutyError.None
assert captureWorkDuty(source, profile, workRecipient(key(2), StateTime(15)), CoreIndex(1),
    cap).error == WorkDutyError.InvalidTime
assert captureWorkDuty(source, profile, workRecipient(key(2), StateTime(24)), CoreIndex(0),
    cap).error == WorkDutyError.UncertainEpoch
assert captureWorkDuty(source, profile, workRecipient(key(102), StateTime(20)), CoreIndex(0),
    cap).error == WorkDutyError.NotAssigned
assert captureWorkDuty(source, profile, workRecipient(key(99), StateTime(20)), CoreIndex(0),
    cap).error == WorkDutyError.NotAssigned
assert captureWorkDuty(source, profile, workRecipient(key(2), StateTime(20)), CoreIndex(high(
    uint64)), cap).error == WorkDutyError.InvalidCore
assert captureWorkDuty(source, default(Parameters), workRecipient(key(2), StateTime(20)), CoreIndex(
    0), cap).error == WorkDutyError.InvalidPolicy
assert not default(WorkDuty).valid and not workRecipient(default(StateEdKey), StateTime(20)).valid
assert captureWorkDuty(source, profile, default(WorkRecipient), CoreIndex(0), cap).error ==
    WorkDutyError.InvalidIdentity
# The current GP null-validator Ed sentinel is02 followed by zeros, not the all-zero key.
assert not workRecipient(nullValidator().ed25519, StateTime(20)).valid
assert captureWorkDuty(source, profile, workRecipient(nullValidator().ed25519, StateTime(20)),
  CoreIndex(0), cap).error == WorkDutyError.InvalidIdentity
var nulled = source.lookup(chapterKey(StateChapter(8))).value.bytes
let nullKey = array[32, byte](nullValidator().ed25519)
for index in 0..<32: nulled[1+336+32+index] = nullKey[
    index] # The second source record's Ed field is genuinely replaced.
assert captureWorkDuty(changed(source, 8, nulled), profile, workRecipient(key(2), StateTime(20)),
  CoreIndex(0), cap).error == WorkDutyError.NotAssigned
# A nine-member current population activates three cores; the previous population can be six without rebinding current indices.
const NineAt20 = [2'u64, 2, 2, 0, 0, 1, 0, 1, 1]
let larger = state(current = 9, previous = 6, slot = 12)
for index in 0..<9:
  let selected = captureWorkDuty(larger, profile, workRecipient(key(index+1), StateTime(20)),
    CoreIndex(NineAt20[index]), cap)
  assert selected.error == WorkDutyError.None, "nine-member source duty"
  assert uint16(selected.value.shardCount) == 9
let excluded = state(offender = true)
let peerOfExcluded = captureWorkDuty(excluded, profile, workRecipient(key(3), StateTime(20)),
  CoreIndex(0), cap)
assert peerOfExcluded.error == WorkDutyError.None
let nulledPeer = peerOfExcluded.value.participantAt(0).value
assert uint16(nulledPeer.index) == 1
let excludedNullKey = array[32, byte](nullValidator().ed25519)
let excludedKey = array[32, byte](nulledPeer.validator.ed25519)
assert excludedKey == excludedNullKey
assert default(WorkDuty).participantCount == 0
assert default(WorkDuty).participantAt(0).error == WorkDutyError.Uninitialized
assert captureWorkDuty(excluded, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0),
    cap).error == WorkDutyError.NotAssigned
# Exact state-component boundaries and real child failures remain distinct from ordinary absent membership.
for chapter in [5'u8, 6, 8, 9, 11]:
  let absent = changed(source, chapter, @[], remove = true)
  let missing = captureWorkDuty(absent, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
  assert missing.error == WorkDutyError.StateFailure and missing.stateError ==
      StateStoreError.MissingKey
  assert uint8(missing.chapter) == chapter
  var bytes = source.lookup(chapterKey(StateChapter(chapter))).value.bytes
  bytes.add(0)
  let suffix = captureWorkDuty(changed(source, chapter, bytes), profile,
    workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
  assert suffix.error == WorkDutyError.InvalidState and uint8(suffix.chapter) == chapter
let malformed = captureWorkDuty(changed(source, 8, @[255'u8]), profile,
  workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
assert malformed.error == WorkDutyError.ComponentFailure
assert malformed.componentError == StateComponentError.Truncated and uint8(malformed.chapter) == 8
let badDisputes = captureWorkDuty(changed(source, 5, @[255'u8]), profile,
  workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
assert badDisputes.error == WorkDutyError.DisputeFailure and badDisputes.disputeError ==
    DisputeStateError.Truncated
var small = cap
small.chapterBytes = ByteLimit(3)
assert captureWorkDuty(source, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0),
    small).error == WorkDutyError.LimitExceeded
small = cap
small.disputeItems = ElementLimit(0)
assert captureWorkDuty(excluded, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0),
    small).disputeError == DisputeStateError.LimitExceeded
failHash(1)
let backend = captureWorkDuty(source, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
assert backend.error == WorkDutyError.AssignmentFailure and backend.assignmentError ==
    GuarantorError.BackendFailure
failHash(0)

proc cycle() =
  ## All copied chapter bytes, decoded rosters/offenders and both assignment tables retire before detached facts return.
  let selected = captureWorkDuty(source, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0), cap)
  assert selected.error == WorkDutyError.None and selected.value.valid
  assert captureWorkDuty(excluded, profile, workRecipient(key(2), StateTime(20)), CoreIndex(0),
      cap).error == WorkDutyError.NotAssigned
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Release actual source-derived planner owners on success and offender refusal.
let after = getOccupiedMem()
assert before == after
recordArcRelease("jamnp_work_duty", 1000, before, after)
echo "JAMNP-S work duty passed"
echo "ARC_RELEASE cycles=1000 unchanged"
