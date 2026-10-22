# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_parallel_annulment_arc_release"}

## Genuine common-source supervisor and junior executions prove the current accpar N selection boundary.
import std/[assertions, syncio]
import ../../../src/state/[accumulation_annulment, accumulation_outcome, accumulation_effects,
  accumulation_dispatch, accumulation_inputs, store]
import ../../../src/pvm/machine
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_accounts, state_layout, state_trie]
import ../../support/[accumulation_batch_context, pvm_accumulation_program,
    pvm_accumulation_context, arc_evidence]

# Annulment owns pure decisions and never recomputes or publishes a state root.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(): AccumulationAnnulmentLimits =
  ## Small independent ceilings bound both original modifications and the complete pair scan.
  AccumulationAnnulmentLimits(outcomes: ElementLimit(2), modified: ElementLimit(8),
      checks: ElementLimit(128))
proc parentCode(target = 99'u64, supervisor = 42'u64, selfWrite = false): seq[byte] =
  ## No-op supervisor calls still mark the junior; an optional genuine self upgrade tests mutually conflicting originals.
  var code: seq[seq[byte]] = @[]
  if selfWrite:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
        registerImmediate(9, 0), registerImmediate(10, 0), @[10'u8, 21]]:
      code.add(instruction) # Mark self before the foreign supervisor mutation.
  for instruction in @[registerImmediate(7, target), registerImmediate(8, supervisor), @[10'u8, 29],
      @[50'u8, 0]]:
    code.add(instruction) # Preserve the ordinary parent program when selfWrite is false.
  guestEnvelope(code)
proc juniorCode(write = true, panic = false, checkpointAfter = false, emit = true,
    reciprocal = false): seq[byte] =
  ## Real provision/checkpoint/upgrade/transfer/yield effects distinguish original and annulled observations.
  var code = @[registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9, 1),
    @[10'u8, 28], @[10'u8, 19]]
  if reciprocal:
    code.add(registerImmediate(7, 42))
    code.add(registerImmediate(8, 99))
    code.add(@[10'u8, 29]) # A matching reverse prior relationship permits modifying the original supervisor too.
  if write:
    code.add(registerImmediate(7, high(uint64)))
    code.add(registerImmediate(8, 65536))
    code.add(registerImmediate(9, 0))
    code.add(registerImmediate(10, 0))
    code.add(@[10'u8, 21]) # Self upgrades remain authorized even with a different effective supervisor.
  if emit:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 42),
        registerImmediate(9, 0), registerImmediate(10, 0), registerImmediate(11, 10),
        registerImmediate(12, 196608), @[10'u8, 22]]:
      code.add(instruction) # Only actual outgoing transfer calls modify the payer.
  code.add(registerImmediate(7, 65536))
  code.add(@[10'u8, 27]) # Yield and provisions alone do not mark the invoking account.
  if checkpointAfter: code.add(@[10'u8, 19]) # Exceptional selection may retain or discard the self mutation.
  if panic: code.add(@[0'u8]) # Genuine guest panic chooses the exceptional context.
  code.add(@[50'u8, 0])
  guestEnvelope(code)
proc fixture(supervisor = 42'u32, incarnation = 0'u32, incoming = false,
    write = true, panic = false, checkpointAfter = false, emit = true,
        handoff = false, mutual = false): BatchFixture =
  ## Amend the authored complete prior before either real execution captures it.
  result = batchFixture(incoming = incoming, firstEnvelope = parentCode(supervisor = (
      if handoff: 99'u64 else: 42'u64), selfWrite = mutual),
    secondEnvelope = juniorCode(write, panic, checkpointAfter, emit, reciprocal = mutual))
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  var metadata = decodeServiceMetadata(result.state.snapshot.value.lookup(key).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  metadata.supervisor = ServiceIndex(supervisor)
  metadata.supervisorCreated = AccountSlot(incarnation)
  let entry = serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(
      ServiceMetadataBytes)).value
  assert result.state.apply([StateWrite(key: key, kind: StateWriteKind.Put,
      value: entry.value)]).error == StateStoreError.None, "annulment witness at source line 59"
  if mutual:
    let parentKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
    var parent = decodeServiceMetadata(result.state.snapshot.value.lookup(parentKey).value.bytes,
        ByteLimit(ServiceMetadataBytes)).value.metadata
    parent.supervisor = ServiceIndex(99)
    parent.supervisorCreated = AccountSlot(0)
    let entry = serviceMetadataEntry(ServiceIndex(42), parent, ByteLimit(
        ServiceMetadataBytes)).value
    assert result.state.apply([StateWrite(key: parentKey, kind: StateWriteKind.Put,
        value: entry.value)]).error == StateStoreError.None, "seed a real matching reverse supervisor before execution"
proc profile(): Parameters =
  ## Tiny fixture balances have zero deposits; genuine deferred transfers still require the exact 128-byte memo profile.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Clear all three complete deposit words.
  for index in 110..<114: wire[index] = 0 # Clear the complete E4 memo-width field.
  wire[110] = 128
  decodeParameters(wire).value
proc original(source: BatchFixture, index: uint64, enabled = true): AccumulationOutcome =
  ## Normalize actual terminal selection; no caller-authored state, gas or modification flag exists.
  let execution = batchExecution(source, index, parameters = profile(), copyLimit = MemoryByteLimit(
      128), transferLimit = ElementLimit(1),
    modifiedAccounts = ElementLimit(if enabled: 8'u64 else: 0'u64))
  assert execution.error == AccumulationDispatchError.None, "original dispatch service ordinal " &
      $index & ": " & $execution.error
  normalizeAccumulationOutcome(execution).value
proc prepared(source: BatchFixture, first, second: AccumulationOutcome): PreparedAccumulationAnnulment =
  ## Only genuine common-source outcomes and their exact original input/map owners construct decisions.
  prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [first, second], policy()).value

let source = fixture()
let first = original(source, 0)
let second = original(source, 1)
assert second.outcomeInfo.value.hasYield and second.outcomeInfo.value.transfers == 1, "annulment witness at source line 75"
assert second.outcomeInfo.value.provisions == 1, "annulment witness at source line 76"
assert second.outcomeContext.value.effectModifiedAccountCount.value == 1, "annulment witness at source line 77"
failHash(1)
let plan = prepared(source, first, second)
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
    first], policy()).value
assert reverse.annulmentDecisionAt(AccumulationAnnulmentIndex(0)).value.annulled, "annulment witness at source line 97"
assert reverse.annulmentInfo.value.annulled == 1, "annulment witness at source line 98"
assert plan.annulmentDecisionAt(AccumulationAnnulmentIndex(high(uint64))).error ==
    AccumulationAnnulmentError.InvalidIndex, "annulment witness at source line 99"
assert plan.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(2)).error ==
    AccumulationAnnulmentError.InvalidIndex, "annulment witness at source line 101"
var copied = chosen
copied.annulled = false
assert plan.annulmentDecisionAt(AccumulationAnnulmentIndex(1)).value.annulled, "annulment witness at source line 105"
var exact = policy()
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
    first], policy())
assert refusal3.error == AccumulationAnnulmentError.DuplicateService, "annulment witness at source line 123"
let refusal4 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [default(
    AccumulationOutcome)], policy())
assert refusal4.error == AccumulationAnnulmentError.InvalidOutcome, "annulment witness at source line 126"
let refusal5 = prepareAccumulationAnnulment(default(PreparedAccumulationInputs),
    source.state.snapshot.value, [], policy())
assert refusal5.error == AccumulationAnnulmentError.InvalidInputs, "annulment witness at source line 129"
let refusal6 = prepareAccumulationAnnulment(source.inputs, default(StateStoreSnapshot), [], policy(
  ))
assert refusal6.error == AccumulationAnnulmentError.InvalidState, "annulment witness at source line 132"
let empty = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [], default(
    AccumulationAnnulmentLimits)).value
assert empty.annulmentInfo.value.outcomes == 0, "annulment witness at source line 135"
let alone = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [second],
    policy()).value
assert alone.annulmentInfo.value.annulled == 0, "absent supervisor execution cannot annul a junior"
assert hashCalls() == 0, "annulment witness at source line 137"
failHash(0)
# Distinct owners and disabled tracking cannot become equivalent common-source certificates.
let other = fixture()
let refusal7 = prepareAccumulationAnnulment(other.inputs, source.state.snapshot.value, [first], policy(
  ))
assert refusal7.error == AccumulationAnnulmentError.SourceMismatch, "annulment witness at source line 143"
let refusal8 = prepareAccumulationAnnulment(source.inputs, other.state.snapshot.value, [first], policy(
  ))
assert refusal8.error == AccumulationAnnulmentError.SourceMismatch, "annulment witness at source line 146"
let disabled = original(source, 0, false)
let refusal9 = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [disabled], policy(
  ))
assert refusal9.error == AccumulationAnnulmentError.InvalidOutcome, "annulment witness at source line 150"
# Genuine incoming transfers mark their recipient even without any account-mutating host call.
let untouched = fixture(write = false, emit = false)
let selected1 = prepared(untouched, original(untouched, 0), original(untouched,
    1))
assert selected1.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
let handoff = fixture(handoff = true)
let handedOff = prepared(handoff, original(handoff, 0), original(handoff, 1))
assert handedOff.annulmentInfo.value.annulled == 1, "use the prior supervisor even after its successful handoff"
let credited = fixture(incoming = true, write = false, emit = false)
let creditedPlan = prepared(credited, original(credited, 0), original(credited, 1))
assert creditedPlan.annulmentInfo.value.annulled == 1, "incoming-credit membership participates in annulment"
for supervisor in [99'u32, 77'u32]:
  let independent = fixture(supervisor = supervisor)
  let selected3 = prepared(independent, original(independent, 0), original(independent,
      1))
  assert selected3.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
let stale = fixture(incarnation = 1)
let selected4 = prepared(stale, original(stale, 0), original(stale, 1))
assert selected4.annulmentInfo.value.annulled == 0, "supervisor and original modification sets select annulment"
for checkpoint in [false, true]:
  let exceptional = fixture(panic = true, checkpointAfter = checkpoint)
  let done = prepared(exceptional, original(exceptional, 0), original(exceptional, 1))
  assert done.annulmentInfo.value.annulled == (if checkpoint: 1 else: 0), "annulment witness at source line 169"
# Both predicates consult original outcomes, even when each cancels the other.
let mutual = fixture(mutual = true)
let mutualFirst = original(mutual, 0)
let mutualSecond = original(mutual, 1)
let mutualPlan = prepared(mutual, mutualFirst, mutualSecond)
assert mutualPlan.annulmentInfo.value.annulled == 2, "mutual conflicts are evaluated simultaneously"
let mutualReverse = prepareAccumulationAnnulment(mutual.inputs, mutual.state.snapshot.value,
    [mutualSecond, mutualFirst], policy()).value
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
let malformedFirst = original(malformed, 0)
let malformedSecond = original(malformed, 1)
let malformedResult = prepareAccumulationAnnulment(malformed.inputs, malformed.state.snapshot.value,
    [malformedFirst, malformedSecond], policy())
assert malformedResult.error == AccumulationAnnulmentError.MalformedState, "corrupt nominee is not self supervision"
let absent = default(PreparedAccumulationAnnulment)
assert absent.annulmentInfo.error == AccumulationAnnulmentError.Uninitialized
assert absent.annulmentPrior.error == AccumulationAnnulmentError.Uninitialized
assert absent.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(0)).error ==
    AccumulationAnnulmentError.Uninitialized
var detached = default(PreparedAccumulationAnnulment)
block released_sources:
  let temporary = fixture()
  detached = prepared(temporary, original(temporary, 0), original(temporary, 1))
assert detached.annulmentDecisionAt(AccumulationAnnulmentIndex(1)).value.annulled, "annulment witness at source line 174"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let retained = prepared(source, first, second)
  assert retained.annulmentInfo.value.annulled == 1, "annulment witness at source line 178"
  assert retained.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(1)).value.provisions == 1, "annulment witness at source line 179"
let after = getOccupiedMem()
assert before == after, "annulment decisions and original owners release across 1000 retained-context cycles"
recordArcRelease("pvm_parallel_annulment", 1000, before, after)
echo "PVM parallel annulment tests passed"
echo "ARC_RELEASE cycles=1000 unchanged"
