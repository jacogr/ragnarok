# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_parallel_account_selection_arc_release"}

## Genuine annulment certificates bind M's logical account to the exact selected prior/invoker/supervisor snapshot.
import std/[assertions, syncio]
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/[annulment as accumulation_annulment,
    outcome as accumulation_outcome, effects as accumulation_effects, inputs as accumulation_inputs]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie]
import ../../support/[accumulation_annulment_context, accumulation_batch_context, arc_evidence]

# Source selection performs no state hashes and publishes no replacement state store.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(): AccumulationAccountSelectionLimits =
  ## Explicit finite ceilings include all original outcome capture and per-row membership/identity work.
  AccumulationAccountSelectionLimits(accounts: ElementLimit(2), outcomes: ElementLimit(2),
      checks: ElementLimit(128))
proc select(source: PreparedAccumulationAnnulment, services: openArray[
    ServiceIndex]): PreparedAccumulationAccountSelection =
  ## Complete only a requested prior-account subset from the actual immutable conflict certificate.
  prepareAccumulationAccountSelection(source, services, policy()).value
let source = annulmentFixture()
let first = annulmentOriginal(source, 0)
let second = annulmentOriginal(source, 1)
let conflicts = annulmentPrepared(source, first, second)
let services = [ServiceIndex(42), ServiceIndex(99)]
failHash(1)
let plan = select(conflicts, services)
let info = plan.accountSelectionInfo.value
assert info.accounts == 2 and info.present == 2 and info.deleted == 0, "complete requested subset, no fabricated new account"
assert info.invokers == 1 and info.supervised == 1, "canceled junior uses its actual supervisor source"
let junior = plan.selectedAccountAt(AccumulationAccountSelectionIndex(1)).value
assert junior.origin == AccumulationAccountOrigin.Supervisor and junior.present, "selected supervisor survives the junior's canceled self mutation"
let parentState = first.outcomeContext.value.effectAccounts.value
assert sameStateSnapshot(plan.selectedAccountSnapshotAt(AccumulationAccountSelectionIndex(1)).value,
    parentState), "retain exact parent context, not equal-root substitution"
let actual = plan.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(1)).value
let prior = decodeServiceMetadata(source.state.snapshot.value.lookup(chapterServiceKey(StateChapter(
    255), ServiceIndex(99))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
assert array[32, byte](actual.codeHash) == array[32, byte](prior.codeHash), "junior's canceled code hash never wins M"
let producer = plan.selectedAccountOutcomeAt(AccumulationAccountSelectionIndex(1)).value
assert uint32(producer.outcomeInfo.value.service) == 42, "physical publication can bind facts to the selected producer"
let reversed = select(conflicts, [ServiceIndex(99), ServiceIndex(42)])
assert reversed.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.origin ==
    AccumulationAccountOrigin.Supervisor, "request order does not change M"
var exact = policy()
exact.checks = ElementLimit(info.checks)
let exactPlan = prepareAccumulationAccountSelection(conflicts, services, exact)
assert exactPlan.error == AccumulationAccountSelectionError.None, "exact actual work grant succeeds"
for mode in 0..<3:
  var short = exact
  case mode
  of 0: short.accounts = ElementLimit(1) # Requested-account descriptor budget.
  of 1: short.outcomes = ElementLimit(1) # Source capture budget is independent of requested rows.
  else: short.checks = ElementLimit(info.checks-1) # Charge before the final selected metadata read.
  let refused = prepareAccumulationAccountSelection(conflicts, services, short)
  assert refused.error == AccumulationAccountSelectionError.LimitExceeded, "each independent local ceiling refuses without a partial candidate"
let duplicate = prepareAccumulationAccountSelection(conflicts, [ServiceIndex(99), ServiceIndex(99)], policy())
assert duplicate.error == AccumulationAccountSelectionError.DuplicateService, "M is a prior-account dictionary"
let absentId = prepareAccumulationAccountSelection(conflicts, [ServiceIndex(77)], policy())
assert absentId.error == AccumulationAccountSelectionError.UnknownService, "new accounts belong to n, not this prior-account selector"
let invalid = prepareAccumulationAccountSelection(default(PreparedAccumulationAnnulment), [], policy())
assert invalid.error == AccumulationAccountSelectionError.InvalidSource, "caller-authored empty decisions cannot authorize selection"
let past = plan.selectedAccountAt(AccumulationAccountSelectionIndex(high(uint64)))
assert past.error == AccumulationAccountSelectionError.InvalidIndex, "bound full-width ordinal before narrowing"
var copied = junior
copied.present = false
copied.origin = AccumulationAccountOrigin.Prior
assert plan.selectedAccountAt(AccumulationAccountSelectionIndex(1)).value.present, "copied descriptors cannot mutate the retained plan"
assert hashCalls() == 0, "selection never recomputes or publishes state roots"
failHash(0)
# Uncontested own modification wins; self-supervision may retain an unchanged invoker context too.
let independent = annulmentFixture(supervisor = 99)
let independentSource = annulmentPrepared(independent, annulmentOriginal(independent, 0),
    annulmentOriginal(independent, 1))
let own = select(independentSource, [ServiceIndex(99)])
assert own.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.origin ==
    AccumulationAccountOrigin.Invoker, "surviving self modification grants own-context precedence"
let uncontested = annulmentFixture(parentTarget = 42)
let uncontestedSource = annulmentPrepared(uncontested, annulmentOriginal(uncontested, 0),
    annulmentOriginal(uncontested, 1))
let uncontestedPlan = select(uncontestedSource, [ServiceIndex(99)])
let uncontestedOrigin = uncontestedPlan.selectedAccountAt(AccumulationAccountSelectionIndex(
    0)).value.origin
assert uncontestedOrigin == AccumulationAccountOrigin.Invoker, "own modified membership wins even while the distinct supervisor executes"
let untouched = annulmentFixture(write = false, emit = false)
let untouchedFirst = annulmentOriginal(untouched, 0)
let untouchedSecond = annulmentOriginal(untouched, 1)
let untouchedSource = annulmentPrepared(untouched, untouchedFirst, untouchedSecond)
let untouchedPlan = select(untouchedSource, [ServiceIndex(99)])
let untouchedOrigin = untouchedPlan.selectedAccountAt(AccumulationAccountSelectionIndex(
    0)).value.origin
assert untouchedOrigin == AccumulationAccountOrigin.Supervisor, "untouched junior uses its active supervisor state"
let untouchedOnly = prepareAccumulationAnnulment(untouched.inputs, untouched.state.snapshot.value, [
    untouchedSecond], annulmentPolicy()).value
let untouchedIdentity = select(untouchedOnly, [ServiceIndex(99)])
let untouchedIdentityOrigin = untouchedIdentity.selectedAccountAt(AccumulationAccountSelectionIndex(
    0)).value.origin
assert untouchedIdentityOrigin == AccumulationAccountOrigin.Prior, "an untouched junior with absent supervisor execution uses identity"
# Use the original parent after it changes supervision in its own candidate.
let handedOff = annulmentFixture(handoff = true)
let handedOffSource = annulmentPrepared(handedOff, annulmentOriginal(handedOff, 0),
    annulmentOriginal(handedOff, 1))
let handoff = select(handedOffSource, [ServiceIndex(99)])
assert handoff.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.origin ==
    AccumulationAccountOrigin.Supervisor, "M resolves supervision against the common prior"
let handedMetadata = handoff.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(0)).value
assert uint32(handedMetadata.supervisor) == 99, "selected parent handoff bytes are retained even though prior authority selected them"
# Missing and canceled original supervisors each contribute prior identity.
let juniorOnly = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [second],
    annulmentPolicy()).value
let ownOnly = select(juniorOnly, [ServiceIndex(99)])
assert ownOnly.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.origin ==
    AccumulationAccountOrigin.Invoker, "missing supervisor cannot cancel a genuine own modification"
let noOutcomes = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
let identity = select(noOutcomes, services)
assert identity.accountSelectionInfo.value.invokers == 0 and
    identity.accountSelectionInfo.value.supervised == 0, "absent executions preserve prior accounts"
let noProducer = identity.selectedAccountOutcomeAt(AccumulationAccountSelectionIndex(0))
assert noProducer.error == AccumulationAccountSelectionError.NoOutcome, "identity carries no fabricated mutating source"
let mutual = annulmentFixture(mutual = true)
let mutualSource = annulmentPrepared(mutual, annulmentOriginal(mutual, 0), annulmentOriginal(mutual, 1))
let canceled = select(mutualSource, services)
assert canceled.accountSelectionInfo.value.invokers == 0 and
    canceled.accountSelectionInfo.value.supervised == 0, "mutual original conflicts select both prior identities"
assert sameStateSnapshot(canceled.selectedAccountSnapshotAt(AccumulationAccountSelectionIndex(
    0)).value, mutual.state.snapshot.value), "annulled supervisor resets to the exact common prior"
# A selected supervisor can delete an existing prior account; absence must never fall back to its old bytes.
let ejected = annulmentFixture(eject = true)
let ejectOutcome = annulmentOriginal(ejected, 0)
let ejectSource = prepareAccumulationAnnulment(ejected.inputs, ejected.state.snapshot.value, [
    ejectOutcome], annulmentPolicy()).value
let deletion = select(ejectSource, [ServiceIndex(99)])
assert deletion.accountSelectionInfo.value.deleted == 1, "selected parent deletion is explicit"
let gone = deletion.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(0))
assert gone.error == AccumulationAccountSelectionError.NoAccount, "deleted metadata cannot be extracted as zero or prior values"
assert not deletion.selectedAccountAt(AccumulationAccountSelectionIndex(0)).value.present, "selected disappearance remains bound to its source"
let absent = default(PreparedAccumulationAccountSelection)
assert absent.accountSelectionInfo.error == AccumulationAccountSelectionError.Uninitialized
assert absent.accountSelectionSource.error == AccumulationAccountSelectionError.Uninitialized
# Malformed unrelated prior rows remain visible to this selector even when not read by invocation conflict checks.
var malformed = annulmentFixture()
let malformedKey = chapterServiceKey(StateChapter(255), ServiceIndex(77))
let malformedApplied = malformed.state.apply([StateWrite(key: malformedKey,
    kind: StateWriteKind.Put, value: @[0'u8])])
assert malformedApplied.error == StateStoreError.None, "author the malformed complete prior before execution captures it"
let malformedSource = annulmentPrepared(malformed, annulmentOriginal(malformed, 0),
    annulmentOriginal(malformed, 1))
let malformedPlan = prepareAccumulationAccountSelection(malformedSource, [ServiceIndex(77)], policy())
assert malformedPlan.error == AccumulationAccountSelectionError.MalformedState, "malformed requested metadata is not a missing account"
var detached = default(PreparedAccumulationAccountSelection)
block released_sources:
  let temporary = annulmentFixture()
  let source = annulmentPrepared(temporary, annulmentOriginal(temporary, 0), annulmentOriginal(
      temporary, 1))
  detached = select(source, services)
assert detached.selectedAccountAt(AccumulationAccountSelectionIndex(1)).value.origin ==
    AccumulationAccountOrigin.Supervisor
let before = getOccupiedMem()
for iteration in 0..<1000:
  let retained = select(conflicts, services)
  assert retained.accountSelectionInfo.value.present == 2
  let metadata = retained.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(1)).value
  assert array[32, byte](metadata.codeHash) == array[32, byte](prior.codeHash)
let after = getOccupiedMem()
assert before == after, "selected source-map handles and copied metadata release across 1000 cycles"
recordArcRelease("pvm_parallel_account_selection", 1000, before, after)
echo "PVM parallel account selection passed"
echo "ARC_RELEASE cycles=1000 unchanged"
