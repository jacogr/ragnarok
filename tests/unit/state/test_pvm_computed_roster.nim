# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_roster_arc_release"}

## Posterior population/core/shard eligibility with genuine epoch shrink, immutable provenance and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[computed_roster, computed_transition, computed_profile, block_transition,
  store]
import ../../../src/codec/[assurances, bounded, state_safrole, state_layout]
import ../../support/[pvm_computed_roster, pvm_computed_state, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after genuine source execution and signed transition construction.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual primitive attempts while checking population eligibility.
proc expect[T](outcome: ComputedRosterResult[T], reason: ComputedRosterError) =
  ## Compare precise selected reasons before guarded extraction.
  assert outcome.error == reason, "computed roster reason: " & $outcome.error
func sameRecord(left, right: StateValidator): bool =
  ## Compare every nominal fixed record field explicitly without introducing production equality operators.
  let keys = array[32, byte](left.bandersnatch) == array[32, byte](right.bandersnatch) and
    array[32, byte](left.ed25519) == array[32, byte](right.ed25519)
  let opaque = array[144, byte](left.bls) == array[144, byte](right.bls) and
    array[128, byte](left.metadata) == array[128, byte](right.metadata)
  keys and opaque
let fixture = rosterFixture(core = 1)
let source = fixture.source
let staged = source.computedTransitionStage.value
let posterior = staged.value.snapshot
let chapter = posterior.lookup(chapterKey(StateChapter(8))).value
assert chapter.byteLength == 2017, "literal canonical six-validator chapter extent"
let limits = ComputedRosterLimits(validators: ElementLimit(6), bytes: ByteLimit(2017))
let done = checkComputedRoster(source, limits).value
assert uint64(done.computedRosterInfo.value.population) == 6, "posterior population, below structural ceiling9"
assert uint64(done.computedRosterInfo.value.activeCores) == 2, "two active cores among three configured"
assert validatorCount(done.computedRosterActive.value).value == 6
assert sameStateSnapshot(done.computedRosterSource.value.computedTransitionStage.value.value.snapshot,
    posterior), "same authenticated posterior owner"
let decoded = decodeStateValidators(chapter.bytes, ValidatorStateConfig(cores: CoreCount(3),
  validators: ElementLimit(9), maxBytes: ByteLimit(10000))).value.value
for index in 0..<6:
  # Ordered fixed-record queries must preserve all 336 bytes from the exact posterior chapter.
  let actual = validatorAt(done.computedRosterActive.value, StateValidatorIndex(uint64(index))).value
  let expected = validatorAt(decoded, StateValidatorIndex(uint64(index))).value
  assert sameRecord(actual, expected), "all posterior record fields retained in order"
let more = ComputedRosterLimits(validators: ElementLimit(1000), bytes: ByteLimit(100000))
expect(checkComputedRoster(source, more), ComputedRosterError.None)
let shortBytes = ComputedRosterLimits(validators: ElementLimit(6), bytes: ByteLimit(2016))
let shortCount = ComputedRosterLimits(validators: ElementLimit(5), bytes: ByteLimit(2017))
expect(checkComputedRoster(source, shortBytes), ComputedRosterError.LimitExceeded)
expect(checkComputedRoster(source, shortCount), ComputedRosterError.LimitExceeded)
expect(checkComputedRoster(source, ComputedRosterLimits()), ComputedRosterError.LimitExceeded)
expect(checkComputedRoster(default(TransitionBoundComputedReport), limits),
    ComputedRosterError.InvalidSource)
expect(default(ComputedRosterResult[RosterEligibleComputedReport]),
    ComputedRosterError.Uninitialized)
expect(default(RosterEligibleComputedReport).computedRosterSource,
    ComputedRosterError.Uninitialized)
expect(default(RosterEligibleComputedReport).computedRosterActive,
    ComputedRosterError.Uninitialized)
expect(default(RosterEligibleComputedReport).computedRosterInfo, ComputedRosterError.Uninitialized)
let inactive = rosterFixture(core = 2).source
expect(checkComputedRoster(inactive, limits), ComputedRosterError.InactiveCore)
let wrongShards = rosterFixture(shards = 9).source
expect(checkComputedRoster(wrongShards, limits), ComputedRosterError.WrongErasureShards)
# A real epoch rotates parent9 to posterior6; parent-based validation would incorrectly accept core2/shards9.
let shrink = rosterFixture(shrink = true, core = 1)
let shrinkParent = shrink.source.computedTransitionSource.value.computedProfileContext.value
assert uint64(shrinkParent.validators) == 9, "genuine configured parent population9"
let shrunk = checkComputedRoster(shrink.source, limits).value
assert uint64(shrunk.computedRosterInfo.value.population) == 6, "actual posterior shrank to6"
assert uint64(shrunk.computedRosterInfo.value.activeCores) == 2
let removedCore = rosterFixture(shrink = true, core = 2).source
expect(checkComputedRoster(removedCore, limits), ComputedRosterError.InactiveCore)
let priorShards = rosterFixture(shrink = true, shards = 9).source
expect(checkComputedRoster(priorShards, limits), ComputedRosterError.WrongErasureShards)
# Copied facts and records cannot replace the retained immutable roster or source.
var facts = shrunk.computedRosterInfo.value
facts.population = ValidatorCount(9)
facts.activeCores = CoreCount(3)
let first = validatorAt(shrunk.computedRosterActive.value, StateValidatorIndex(0)).value
var copied = first
copied.ed25519 = default(StateEdKey)
assert sameRecord(validatorAt(shrunk.computedRosterActive.value, StateValidatorIndex(0)).value, first)
assert uint64(shrunk.computedRosterInfo.value.population) == 6
var caller = shrink.original
changeState(caller)
assert sameStateSnapshot(shrunk.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state,
    shrink.original.snapshot.value), "caller publication preserves original source"
reset(1)
expect(checkComputedRoster(source, limits), ComputedRosterError.None)
expect(checkComputedRoster(removedCore, limits), ComputedRosterError.InactiveCore)
expect(checkComputedRoster(priorShards, limits), ComputedRosterError.WrongErasureShards)
expect(checkComputedRoster(source, shortCount), ComputedRosterError.LimitExceeded)
assert hashes() == 0, "roster eligibility performs no new hashes"
reset(0)
proc detached(): RosterEligibleComputedReport =
  ## Retain original source, authenticated posterior and decoded records after every local source handle retires.
  let fixture = rosterFixture(shrink = true)
  checkComputedRoster(fixture.source, ComputedRosterLimits(validators: ElementLimit(6),
      bytes: ByteLimit(2017))).value
let retained = detached()
assert validatorCount(retained.computedRosterActive.value).value == 6
assert uint64(retained.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.validators) == 9
proc cycle(source, inactive, wrong: TransitionBoundComputedReport, limits,
    short: ComputedRosterLimits) =
  ## Release decoded records, complete shared provenance and refused alternatives without re-execution or signing.
  let bound = checkComputedRoster(source, limits).value
  discard bound.computedRosterActive.value
  discard bound.computedRosterSource.value
  discard bound.computedRosterInfo.value
  expect(checkComputedRoster(inactive, limits), ComputedRosterError.InactiveCore)
  expect(checkComputedRoster(wrong, limits), ComputedRosterError.WrongErasureShards)
  expect(checkComputedRoster(source, short), ComputedRosterError.LimitExceeded)
cycle(source, removedCore, priorShards, limits, shortCount)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, removedCore, priorShards, limits, shortCount)
let after = getOccupiedMem()
assert before == after, "computed roster ARC release"
recordArcRelease("pvm_computed_roster", 1000, before, after)
echo "PVM computed roster passed"
echo "ARC_RELEASE cycles=1000 unchanged"
