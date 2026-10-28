# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_parallel_annulment_arc_release"}

## Genuine common-source supervisor and junior executions prove the current accpar N selection boundary.
import std/assertions
import std/syncio
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/store as state_store
import ../../../src/pvm/machine as pvm_machine
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../support/state_accumulation_batch_context
import ../../support/pvm_accumulation_program
import ../../support/pvm_accumulation_context
import ../../support/state_accumulation_annulment_context
import ../../support/testing_arc_evidence

# Annulment owns pure decisions and never recomputes or publishes a state root.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
let source = annulmentFixture()
let first = annulmentOriginal(source, 0)
let second = annulmentOriginal(source, 1)
assert second.outcomeInfo.value.hasYield and second.outcomeInfo.value.transfers == 1, "annulment witness at source line 75"
assert second.outcomeInfo.value.provisions == 1, "annulment witness at source line 76"
assert second.outcomeContext.value.effectModifiedAccountCount.value == 1, "annulment witness at source line 77"
failHash(1)
let plan = annulmentPrepared(source, first, second)
assert plan.annulmentInfo.value.outcomes == 2 and plan.annulmentInfo.value.annulled == 1, "annulment witness at source line 80"
let chosen = plan.annulmentDecisionAt(AccumulationAnnulmentIndex(1)).value
assert chosen.annulled and uint32(chosen.service) == 99 and uint32(chosen.supervisor) == 42, "annulment witness at source line 82"
assert not plan.annulmentDecisionAt(AccumulationAnnulmentIndex(0)).value.annulled, "annulment witness at source line 83"
let selected = plan.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(1)).value
assert not selected.hasYield and selected.transfers == 0, "annulment witness at source line 85"
assert uint64(selected.gasUsed) == uint64(second.outcomeInfo.value.gasUsed), "annulment witness at source line 86"
assert selected.provisions == second.outcomeInfo.value.provisions, "annulment witness at source line 87"
assert plan.annulmentSelectedModifiedCountAt(AccumulationAnnulmentIndex(1)).value == 0, "annulment witness at source line 88"
assert sameStateSnapshot(plan.annulmentSelectedAccountsAt(AccumulationAnnulmentIndex(1)).value,
  source.state.snapshot.value), "annulment witness at source line 89"
assert not sameStateSnapshot(second.outcomeContext.value.effectAccounts.value,
    source.state.snapshot.value), "annulment witness at source line 91"
assert plan.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(
    1)).value.outcomeInfo.value.transfers == 1, "annulment witness at source line 93"
let reverse = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [second,
    first], annulmentPolicy()).value
assert reverse.annulmentDecisionAt(AccumulationAnnulmentIndex(0)).value.annulled, "annulment witness at source line 97"
assert reverse.annulmentInfo.value.annulled == 1, "annulment witness at source line 98"
assert plan.annulmentDecisionAt(AccumulationAnnulmentIndex(high(uint64))).error ==
    AccumulationAnnulmentError.InvalidIndex, "annulment witness at source line 99"
assert plan.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(2)).error ==
    AccumulationAnnulmentError.InvalidIndex, "annulment witness at source line 101"
var copied = chosen
copied.annulled = false
assert plan.annulmentDecisionAt(AccumulationAnnulmentIndex(1)).value.annulled, "annulment witness at source line 105"
var exact = annulmentPolicy()
exact.checks = ElementLimit(plan.annulmentInfo.value.checks)
let refusal1 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [first,
    second], exact)
assert refusal1.error == AccumulationAnnulmentError.None, "annulment witness at source line 110"
for mode in 0..<3:
  var short = exact
  case mode
  of 0: short.outcomes = ElementLimit(1) # Every genuine source consumes one source slot.
  of 1: short.modified = ElementLimit(1) # Both original membership sets count even when one is annulled.
  else: short.checks = ElementLimit(plan.annulmentInfo.value.checks-1) # Work is charged before the last actual predicate.
  let refusal2 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [first,
      second],
      short)
  assert refusal2.error == AccumulationAnnulmentError.LimitExceeded, "annulment witness at source line 120"
let refusal3 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [first,
    first], annulmentPolicy())
assert refusal3.error == AccumulationAnnulmentError.DuplicateService, "annulment witness at source line 123"
let refusal4 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [default(
    AccumulationOutcome)], annulmentPolicy())
assert refusal4.error == AccumulationAnnulmentError.InvalidOutcome, "annulment witness at source line 126"
let refusal5 = prepareAccumulationAnnulment(default(PreparedAccumulationInputs),
    source.state.snapshot.value, [], annulmentPolicy())
assert refusal5.error == AccumulationAnnulmentError.InvalidInputs, "annulment witness at source line 129"
let refusal6 = prepareAccumulationAnnulment(source.inputs, default(StateStoreSnapshot), [],
    annulmentPolicy(
  ))
assert refusal6.error == AccumulationAnnulmentError.InvalidState, "annulment witness at source line 132"
let empty = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [], default(
    AccumulationAnnulmentLimits)).value
assert empty.annulmentInfo.value.outcomes == 0, "annulment witness at source line 135"
let alone = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [second],
    annulmentPolicy()).value
assert alone.annulmentInfo.value.annulled == 0, "absent supervisor execution cannot annul a junior"
assert hashCalls() == 0, "annulment witness at source line 137"
failHash(0)
# Distinct owners and disabled tracking cannot become equivalent common-source certificates.
let other = annulmentFixture()
let refusal7 = prepareAccumulationAnnulment(other.inputs, source.state.snapshot.value, [first],
    annulmentPolicy(
  ))
assert refusal7.error == AccumulationAnnulmentError.SourceMismatch, "annulment witness at source line 143"
let refusal8 = prepareAccumulationAnnulment(source.inputs, other.state.snapshot.value, [first],
    annulmentPolicy(
  ))
assert refusal8.error == AccumulationAnnulmentError.SourceMismatch, "annulment witness at source line 146"
let disabled = annulmentOriginal(source, 0, false)
let refusal9 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [disabled],
    annulmentPolicy(
  ))
assert refusal9.error == AccumulationAnnulmentError.InvalidOutcome, "annulment witness at source line 150"
# Genuine incoming transfers mark their recipient even without any account-mutating host call.
let untouched = annulmentFixture(write = false, emit = false)
let selected1 = annulmentPrepared(untouched, annulmentOriginal(untouched, 0), annulmentOriginal(
    untouched, 1))
assert selected1.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
let handoff = annulmentFixture(handoff = true)
let handedOff = annulmentPrepared(handoff, annulmentOriginal(handoff, 0), annulmentOriginal(handoff, 1))
assert handedOff.annulmentInfo.value.annulled == 1, "use the prior supervisor even after its successful handoff"
let credited = annulmentFixture(incoming = true, write = false, emit = false)
let creditedPlan = annulmentPrepared(credited, annulmentOriginal(credited, 0), annulmentOriginal(
    credited, 1))
assert creditedPlan.annulmentInfo.value.annulled == 1, "incoming-credit membership participates in annulment"
for supervisor in [99'u32, 77'u32]:
  let independent = annulmentFixture(supervisor = supervisor)
  let selected3 = annulmentPrepared(independent, annulmentOriginal(independent, 0),
      annulmentOriginal(independent, 1))
  assert selected3.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
let stale = annulmentFixture(incarnation = 1)
let selected4 = annulmentPrepared(stale, annulmentOriginal(stale, 0), annulmentOriginal(stale, 1))
assert selected4.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
for checkpoint in [false, true]:
  let exceptional = annulmentFixture(panic = true, checkpointAfter = checkpoint)
  let done = annulmentPrepared(exceptional, annulmentOriginal(exceptional, 0), annulmentOriginal(
      exceptional, 1))
  assert done.annulmentInfo.value.annulled == (if checkpoint: 1 else: 0), "annulment witness at source line 169"
# Both predicates consult original outcomes, even when each cancels the other.
let mutual = annulmentFixture(mutual = true)
let mutualFirst = annulmentOriginal(mutual, 0)
let mutualSecond = annulmentOriginal(mutual, 1)
let mutualPlan = annulmentPrepared(mutual, mutualFirst, mutualSecond)
assert mutualPlan.annulmentInfo.value.annulled == 2, "mutual conflicts are evaluated simultaneously"
let mutualReverse = prepareAccumulationAnnulment(mutual.inputs, mutual.state.snapshot.value,
    [mutualSecond, mutualFirst], annulmentPolicy()).value
assert mutualReverse.annulmentInfo.value.annulled == 2, "original-set cancellation cannot depend on execution array order"
# Malformed noninvoking nominee metadata is a refusal, never an absent-supervisor fallback.
var malformed = batchFixture(incoming = false, firstEnvelope = guestEnvelope([@[50'u8, 0]]),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]))
let malformedKey = chapterServiceKey(StateChapter(255), ServiceIndex(99))
var malformedSelf = decodeServiceMetadata(malformed.state.snapshot.value.lookup(
    malformedKey).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
malformedSelf.supervisor = ServiceIndex(77)
let malformedEntry = serviceMetadataEntry(ServiceIndex(99), malformedSelf, ByteLimit(
    ServiceMetadataBytes)).value
let nomineeKey = chapterServiceKey(StateChapter(255), ServiceIndex(77))
assert malformed.state.apply([StateWrite(key: malformedKey, kind: StateWriteKind.Put,
    value: malformedEntry.value), StateWrite(key: nomineeKey, kind: StateWriteKind.Put, value: @[
        0'u8])]).error == StateStoreError.None, "authentic malformed prior belongs to both executions"
let malformedFirst = annulmentOriginal(malformed, 0)
let malformedSecond = annulmentOriginal(malformed, 1)
let malformedResult = prepareAccumulationAnnulment(malformed.inputs, malformed.state.snapshot.value,
    [malformedFirst, malformedSecond], annulmentPolicy())
assert malformedResult.error == AccumulationAnnulmentError.MalformedState, "corrupt nominee is not self supervision"
let absent = default(PreparedAccumulationAnnulment)
assert absent.annulmentInfo.error == AccumulationAnnulmentError.Uninitialized
assert absent.annulmentPrior.error == AccumulationAnnulmentError.Uninitialized
assert absent.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(0)).error ==
    AccumulationAnnulmentError.Uninitialized
var detached = default(PreparedAccumulationAnnulment)
block released_sources:
  let temporary = annulmentFixture()
  detached = annulmentPrepared(temporary, annulmentOriginal(temporary, 0), annulmentOriginal(
      temporary, 1))
assert detached.annulmentDecisionAt(AccumulationAnnulmentIndex(1)).value.annulled, "annulment witness at source line 174"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let retained = annulmentPrepared(source, first, second)
  assert retained.annulmentInfo.value.annulled == 1, "annulment witness at source line 178"
  assert retained.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(1)).value.provisions == 1, "annulment witness at source line 179"
let after = getOccupiedMem()
assert before == after, "annulment decisions and original owners release across 1000 retained-context cycles"
recordArcRelease("pvm_parallel_annulment", 1000, before, after)
echo "PVM parallel annulment tests passed"
echo "ARC_RELEASE cycles=1000 unchanged"
