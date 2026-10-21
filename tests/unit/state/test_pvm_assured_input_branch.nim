# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_input_branch_arc_release"}

## Actual list counts branch after a real write; panic discards regular mutations and preserves the original exceptional account.

import std/[assertions, syncio]
import ../../../src/state/[assured_chain, assured_composition, assured_execution, assured_queue,
  accumulation_execution, accumulation_round, accumulation_inputs, accumulation_batch,
  accumulation_provisions, accumulation_outcome, accumulation_context, accumulation_effects,
  accumulation_consensus, accumulation_runner, accumulation_dispatch, store]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_service_values,
  state_statistics, state_workqueues]
import ../../../src/pvm/[machine, step]
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## The account survives discarded writes; decode its exact canonical fields at each retained full-map owner.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, present: bool) =
  ## Check selected storage bytes and counters independently of the successful publication result.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  let found = state.lookup(key)
  let account = metadata(state)
  if present:
    assert found.error == StateStoreError.None and found.value.bytes == @[1'u8, 22, 23]
    assert uint32(account.storageItems) == 1 and uint64(account.storageBytes) == 38
  else:
    assert found.error == StateStoreError.MissingKey
    assert uint32(account.storageItems) == 0 and uint64(account.storageBytes) == 0
  assert uint64(account.balance) == 50
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Execute actual count fetch/load/write/branch instructions with the original source parameters and runner ceilings.
  let outcome = executeAssuredAccumulation(fixture.queue, assuredExecutionConfig(fixture.queue))
  if outcome.error != AssuredExecutionError.None:
    echo "input-branch execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Compose the actually selected exceptional account without replaying initial guest work.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None: echo "input-branch composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
let fixture = assuredOutcomeFixture(ComputedStorageMode.FetchBranchPanic)
let original = fixture.state.snapshot.value
let oldView = fixture.view
storage(original, true)
assert uint32(metadata(original).lastAccumulation) == 2
let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
assert first.outcomeInfo.value.dimension == AccumulationDimension.Regular
storage(first.outcomeContext.value.effectAccounts.value, true)
let firstInputs = fixture.first.executionRound.value.roundProjection.value.roundInputs.value
assert firstInputs.invocationServiceAt(InvocationServiceIndex(0)).value.operands == 1
let source = execute(fixture)
let completed = source.assuredExecutionCompleted.value
let info = completed.executionInfo.value
assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
assert info.batch.selfWrites == 0 and info.batch.selfValueBytes == 0
assert info.batch.deletedAccounts == 0 and info.batch.createdAccounts == 0
assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
let nextInputs = completed.executionRound.value.roundProjection.value.roundInputs.value
assert nextInputs.invocationServiceAt(InvocationServiceIndex(0)).value.operands == 2
assert uint64(info.gasUsed) > 2735 and uint64(info.gasUsed) <= 4729
let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
let terminal = selected.outcomeInfo.value
assert terminal.termination == AccumulationTermination.Panic and terminal.dimension ==
    AccumulationDimension.Exceptional
assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
storage(selected.outcomeContext.value.effectAccounts.value, true)
let config = assuredExecutionConfig(fixture.queue)
var minimal = config
minimal.runner.accountWriteKeys = ElementLimit(0)
minimal.runner.completion.batch.selfWrites = ElementLimit(0)
minimal.runner.completion.batch.selfValueBytes = ByteLimit(0)
let discarded = executeAssuredAccumulation(fixture.queue, minimal)
assert discarded.error == AssuredExecutionError.None
assert discarded.value.assuredExecutionCompleted.value.executionInfo.value.batch.selfWrites == 0
storage(discarded.value.assuredExecutionCompleted.value.executionBatch.value.batchOutcomeAt(
    AccumulationProvisionSourceIndex(0)).value.outcomeContext.value.effectAccounts.value, true)
var short = config
short.runner.copyBytes = MemoryByteLimit(2)
let copy = executeAssuredAccumulation(fixture.queue, short)
assert copy.error == AssuredExecutionError.RunnerFailure
assert copy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert copy.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
short = config
short.runner.calls = typeof(short.runner.calls)(1)
let calls = executeAssuredAccumulation(fixture.queue, short)
assert calls.error == AssuredExecutionError.RunnerFailure
assert calls.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert calls.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
assert calls.runnerFailure.dispatchFailure.executionError == StepError.HostCallLimitExceeded
let composed = compose(source)
let candidate = composed.assuredCompositionPlan.value.accumulationConsensusState.value
storage(candidate, true)
assert uint32(metadata(candidate).lastAccumulation) == 3
assert array[32, byte](metadata(candidate).codeHash) == array[32, byte](metadata(original).codeHash)
let queueConfig = assuredCompositionConfig().composition.ready.queues
assert decodeAccumulatedState(candidate.lookup(chapterKey(StateChapter(15))).value.bytes,
    queueConfig).value.snapshot.accumulatedInfo.value.items == 3
let activity = decodeActivityState(candidate.lookup(chapterKey(StateChapter(13))).value.bytes,
  ActivityConfig(cores: queueConfig.cores, current: typeof(
      fixture.view.bestBlock.value.activeValidators)(9), previous: typeof(
      fixture.view.bestBlock.value.activeValidators)(6), maxServices: ElementLimit(4),
      maxBytes: ByteLimit(10000))).value.snapshot
let counters = activity.serviceActivityAt(StatisticsServiceIndex(0)).value.statistics
assert uint64(counters.counters[ServiceMeasure.AccumulationCount]) == 2
assert uint64(counters.counters[ServiceMeasure.RefinementCount]) == 0
assert uint64(counters.accumulationGas) == uint64(info.gasUsed)
var state = fixture.state
var view = fixture.view
let published = advanceAssuredChain(state, view, composed)
assert published.error == AssuredChainError.None
assert published.value.assuredChainBlock.value.slot == 3 and view.retainedCount == 3 and
    view.finalizedBlock.value.slot == 1
assert sameStateSnapshot(state.snapshot.value, candidate)
storage(published.value.assuredChainSnapshot.value, true)
for field in low(Parameter)..high(Parameter):
  assert published.value.assuredChainBlock.value.chainParameters.get(field) ==
      source.assuredExecutionParameters.value.get(
      field) # Actual data-driven exceptional selection retains the original complete chain tuple.
assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
storage(original, true)
assert uint32(metadata(original).lastAccumulation) == 2
proc cycle(fixture: AssuredOutcomeFixture) =
  ## Execute the real input branch, compose and publish retained exceptional storage, then release every successor owner.
  let source = compose(execute(fixture))
  var state = fixture.state
  var view = fixture.view
  let published = advanceAssuredChain(state, view, source)
  assert published.error == AssuredChainError.None
  storage(published.value.assuredChainSnapshot.value, true)
cycle(fixture)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixture) # The original parent keeps its key while each actual panic/canonical child retires completely.
let after = getOccupiedMem()
assert before == after, "assured input branch ARC release"
recordArcRelease("pvm_assured_input_branch", 1000, before, after)
echo "PVM assured input branch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
