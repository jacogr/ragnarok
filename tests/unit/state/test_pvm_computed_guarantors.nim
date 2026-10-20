# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_guarantors_arc_release"}

## Exact posterior assignments, two rotation freshness bounds, cumulative exclusions and complete failure release.

import std/[assertions, syncio]
import ../../../src/state/[computed_guarantors, computed_roster, computed_transition,
  computed_profile,
  block_transition, block_admission, guarantors, store]
import ../../../src/codec/[bounded, assurances, guarantees, header, state_safrole, state_layout, state_disputes]
import ../../support/[pvm_computed_guarantors, pvm_computed_state, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Inject actual hash provider refusal only after original signed/PVM sources are complete.
proc after(successes: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after actual completed hash calls to exercise prior-table rollback.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe real shuffle attempts and query purity.
proc expect[T](outcome: ComputedGuarantorResult[T], reason: ComputedGuarantorError) =
  ## Compare precise selected refusal before application extraction.
  assert outcome.error == reason, "computed guarantor reason: " & $outcome.error
# Independent hashlib zero-entropy shrinking-swap reference gives permutation6=[5,2,1,4,3,0]
# and permutation9=[2,1,0,5,3,8,4,6,7]; divide by3 then rotate modulo actual active cores.
const Current6 = [1'u64, 0, 0, 1, 1, 0]
const Rotated6 = [0'u64, 1, 1, 0, 0, 1]
const Prior9 = [2'u64, 2, 2, 0, 0, 1, 0, 1, 1]
let limits = guarantorLimits()
let source = guarantorFixture()
let ordinary = prepareComputedGuarantors(source, limits).value
for index in 0..<6:
  # Literal independent core labels distinguish shuffled validator ordinal from assigned core.
  let selected = ordinary.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(uint16(index)))
  expect(selected, if Current6[index] == 0: ComputedGuarantorError.None else: ComputedGuarantorError.WrongAssignment)
expect(ordinary.computedGuarantorAt(GuaranteeSlot(0), GuarantorIndex(1)),
    ComputedGuarantorError.None)
expect(ordinary.computedGuarantorAt(GuaranteeSlot(3), GuarantorIndex(1)),
    ComputedGuarantorError.InvalidSlot)
expect(ordinary.computedGuarantorAt(GuaranteeSlot(high(uint32)), GuarantorIndex(1)),
    ComputedGuarantorError.InvalidSlot)
expect(ordinary.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(6)),
    ComputedGuarantorError.InvalidIndex)
expect(ordinary.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(high(uint16))),
    ComputedGuarantorError.InvalidIndex)
let original = ordinary.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state
var caller = forkStateStore(original).value
changeState(caller)
assert not sameStateSnapshot(caller.snapshot.value, original), "caller published a separate complete-map version"
assert sameStateSnapshot(ordinary.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state,
  original), "retained original source is isolated from caller publication"
var loose = limits
loose.roster.validators = ElementLimit(high(uint64))
expect(prepareComputedGuarantors(source, loose), ComputedGuarantorError.None)
let sameEpochSource = guarantorFixture(target = 8)
let sameEpoch = prepareComputedGuarantors(sameEpochSource, limits).value
for index in 0..<6:
  # Both tables use active6 within the same epoch, with prior rotation labels offset by one.
  expect(sameEpoch.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(uint16(index))),
    if Current6[index] == 0: ComputedGuarantorError.None else: ComputedGuarantorError.WrongAssignment)
  expect(sameEpoch.computedGuarantorAt(GuaranteeSlot(4), GuarantorIndex(uint16(index))),
    if Rotated6[index] == 0: ComputedGuarantorError.None else: ComputedGuarantorError.WrongAssignment)
expect(sameEpoch.computedGuarantorAt(GuaranteeSlot(3), GuarantorIndex(0)),
    ComputedGuarantorError.InvalidSlot)
expect(sameEpoch.computedGuarantorAt(GuaranteeSlot(9), GuarantorIndex(0)),
    ComputedGuarantorError.InvalidSlot)
let crossingSource = guarantorFixture(shrink = true)
let crossing = prepareComputedGuarantors(crossingSource, limits).value
for index in 0..<9:
  # Prior rotation crosses the epoch boundary and selects posterior previous9, not active6.
  expect(crossing.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(uint16(index))),
    if Prior9[index] == 0: ComputedGuarantorError.None else: ComputedGuarantorError.WrongAssignment)
expect(crossing.computedGuarantorAt(GuaranteeSlot(7), GuarantorIndex(3)),
    ComputedGuarantorError.InvalidSlot)
expect(crossing.computedGuarantorAt(GuaranteeSlot(13), GuarantorIndex(1)),
    ComputedGuarantorError.InvalidSlot)
expect(crossing.computedGuarantorAt(GuaranteeSlot(12), GuarantorIndex(6)),
    ComputedGuarantorError.InvalidIndex)
let coreOneSource = guarantorFixture(shrink = true, core = 1)
let coreOne = prepareComputedGuarantors(coreOneSource, limits).value
let ninth = coreOne.computedGuarantorAt(GuaranteeSlot(11), GuarantorIndex(8)).value
assert uint64(ninth.core) == 1, "larger previous roster remains selectable for a currently active computed core"
let snapshot = coreOneSource.computedRosterSource.value.computedTransitionStage.value.value.snapshot
let previous = decodeStateValidators(snapshot.lookup(chapterKey(StateChapter(9))).value.bytes,
  ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9), maxBytes: ByteLimit(
      3025))).value.value
assert array[32, byte](ninth.validator.ed25519) == array[32, byte](validatorAt(previous,
    StateValidatorIndex(8)).value.ed25519)
let excludedSource = guarantorFixture(offender = true)
let excluded = prepareComputedGuarantors(excludedSource, limits).value
let step = excludedSource.computedRosterSource.value.computedTransitionStage.value.value
assert headerInfo(step.admitted.admittedHeader).value.unsigned.offenders == 0, "earlier cumulative offender is absent from this block marker"
expect(excluded.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(5)),
    ComputedGuarantorError.IneligibleValidator)
expect(excluded.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(1)),
    ComputedGuarantorError.None)
var short = limits
short.roster.bytes = ByteLimit(3024)
expect(prepareComputedGuarantors(crossingSource, short), ComputedGuarantorError.LimitExceeded)
var few = limits
few.roster.validators = ElementLimit(8)
expect(prepareComputedGuarantors(crossingSource, few), ComputedGuarantorError.LimitExceeded)
var judgments = limits
judgments.judgments.maxBytes = ByteLimit(35)
expect(prepareComputedGuarantors(excludedSource, judgments), ComputedGuarantorError.LimitExceeded)
var offenders = limits
offenders.offenders = ElementLimit(0)
expect(prepareComputedGuarantors(excludedSource, offenders), ComputedGuarantorError.LimitExceeded)
let invalid = guarantorFixture(rotation = 5)
expect(prepareComputedGuarantors(invalid, limits), ComputedGuarantorError.InvalidConfig)
let tooLong = guarantorFixture(rotation = 65535)
reset(1)
expect(prepareComputedGuarantors(tooLong, limits), ComputedGuarantorError.InvalidConfig)
expect(prepareComputedGuarantors(invalid, limits), ComputedGuarantorError.InvalidConfig)
assert hashes() == 0, "invalid original rotation profiles refuse before hash attempts"
reset(0)
expect(prepareComputedGuarantors(default(RosterEligibleComputedReport), limits),
    ComputedGuarantorError.InvalidSource)
expect(default(ComputedGuarantorResult[ComputedGuarantors]), ComputedGuarantorError.Uninitialized)
expect(default(ComputedGuarantors).computedGuarantorSource, ComputedGuarantorError.Uninitialized)
expect(default(ComputedGuarantors).computedGuarantorAt(GuaranteeSlot(0), GuarantorIndex(0)),
    ComputedGuarantorError.Uninitialized)
# Existing source and all prior checks stay usable when either current or later prior shuffle hashing refuses.
reset(1)
expect(prepareComputedGuarantors(crossingSource, limits), ComputedGuarantorError.BackendFailure)
assert hashes() == 1, "early actual provider refusal"
after(1)
expect(prepareComputedGuarantors(crossingSource, limits), ComputedGuarantorError.BackendFailure)
assert hashes() == 2, "completed current table discarded on first prior hash refusal"
after(2)
expect(prepareComputedGuarantors(crossingSource, limits), ComputedGuarantorError.BackendFailure)
assert hashes() == 3, "later prior hash refusal discards every partial table"
reset(1)
discard crossing.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(3)).value
discard crossing.computedGuarantorSource.value
assert hashes() == 0, "queries perform no hashes"
reset(0)
var copied = ninth
copied.validator.ed25519 = default(StateEdKey)
assert array[32, byte](coreOne.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(
    8)).value.validator.ed25519) == array[32, byte](ninth.validator.ed25519)
proc detached(): ComputedGuarantors =
  ## Retain original computation and posterior tables after every caller source handle retires.
  let source = guarantorFixture(shrink = true, core = 1)
  prepareComputedGuarantors(source, guarantorLimits()).value
let retained = detached()
assert uint64(retained.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(8)).value.core) == 1
proc cycle(source: RosterEligibleComputedReport, limits: ComputedGuarantorLimits) =
  ## Retire full current/prior tables and both early/late refused planning alternatives.
  let done = prepareComputedGuarantors(source, limits).value
  discard done.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(3)).value
  after(1)
  expect(prepareComputedGuarantors(source, limits), ComputedGuarantorError.BackendFailure)
  reset(0)
cycle(crossingSource, limits)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(crossingSource, limits)
let occupied = getOccupiedMem()
assert before == occupied, "computed guarantor ARC release"
recordArcRelease("pvm_computed_guarantors", 1000, before, occupied)
echo "PVM computed guarantors passed"
echo "ARC_RELEASE cycles=1000 unchanged"
