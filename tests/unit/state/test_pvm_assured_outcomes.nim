# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_outcomes_arc_release"}

## Original guest modes retain authentic reports while successor aggregation changes gas exhaustion into real regular commits.

import std/[assertions, syncio]
import ../../../src/state/assured/[chain as assured_chain, composition as assured_composition,
    execution as assured_execution, queue as assured_queue]
import ../../../src/state/accumulation/[execution as accumulation_execution,
    round as accumulation_round, queue as accumulation_queue, inputs as accumulation_inputs,
    batch as accumulation_batch, provisions as accumulation_provisions,
    outcome as accumulation_outcome, effects as accumulation_effects,
    context as accumulation_context, consensus as accumulation_consensus,
    finalization as accumulation_finalization, runner as accumulation_runner]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    layout as state_layout, statistics as state_statistics, workqueues as state_workqueues]
import ../../../src/codec/work/digest as work_digest
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

func initialStorage(mode: ComputedStorageMode): seq[byte] =
  ## Literal first-block exceptional/checkpoint oracle differs from the next block's doubled-credit oracle.
  case mode
  of ComputedStorageMode.Commit, ComputedStorageMode.CheckpointPanic,
      ComputedStorageMode.CheckpointOutOfGas: @[21'u8, 22, 23]
  of ComputedStorageMode.CheckpointCommit: @[22'u8, 23]
  else: @[] # Panic, underfunded and uncheckpointed exhaustion retain absent storage.
func successorStorage(mode: ComputedStorageMode): seq[byte] =
  ## Both formerly exhausted guests now afford the second write; an explicit panic still selects its real implication.
  case mode
  of ComputedStorageMode.Commit, ComputedStorageMode.CheckpointPanic: @[21'u8, 22, 23]
  of ComputedStorageMode.CheckpointCommit, ComputedStorageMode.OutOfGas,
      ComputedStorageMode.CheckpointOutOfGas: @[22'u8, 23]
  else: @[] # Original funding and uncheckpointed panic do not change when gas credits aggregate.
func originalCredit(mode: ComputedStorageMode): uint64 =
  ## Published digest gas is authored before first computation and never patched for successor execution.
  if mode in {ComputedStorageMode.OutOfGas, ComputedStorageMode.CheckpointOutOfGas}: 3500'u64
  else: 10000'u64 # Other original modes retain the ordinary declared credit.
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode exact canonical account metadata from each retained full-map owner.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, expected: openArray[byte]) =
  ## Absence differs from a present empty value; footprint and item count follow the actual stored byte length.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  let found = state.lookup(key)
  let account = metadata(state)
  if expected.len == 0:
    assert found.error == StateStoreError.MissingKey
    assert uint32(account.storageItems) == 0 and uint64(account.storageBytes) == 0
  else:
    assert found.error == StateStoreError.None and found.value.bytes == @expected
    assert uint32(account.storageItems) == 1 and uint64(account.storageBytes) == uint64(
        35+expected.len)
proc completed(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Execute both actual assured reports together; report precise local failures rather than replacing a guest verdict.
  let outcome = executeAssuredAccumulation(fixture.queue, assuredExecutionConfig(fixture.queue))
  if outcome.error != AssuredExecutionError.None:
    echo "successor execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc composed(execution: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Drive genuine guest completion to actual terminal history and full maintained state composition.
  let outcome = composeAssuredState(execution, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None:
    echo "successor composition ", outcome.error
    if outcome.error == AssuredCompositionError.DriverFailure: echo "driver ",
        outcome.driverFailure.error
    if outcome.error == AssuredCompositionError.CompositionFailure: echo "phase ",
        outcome.compositionFailure.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
proc witness(mode: ComputedStorageMode): AssuredOutcomeFixture =
  ## Compare original and successor real terminals, then publish the exact new selected implications with both handles updated together.
  let fixture = assuredOutcomeFixture(mode)
  let original = fixture.state.snapshot.value
  let priorView = fixture.view
  storage(original, initialStorage(mode))
  assert uint32(metadata(original).lastAccumulation) == 2
  let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let firstInfo = first.outcomeInfo.value
  let credit = originalCredit(mode)
  assert uint64(fixture.first.executionInfo.value.round.reportGas) == credit
  if mode in {ComputedStorageMode.OutOfGas, ComputedStorageMode.CheckpointOutOfGas}:
    assert firstInfo.termination == AccumulationTermination.OutOfGas
    assert firstInfo.dimension == AccumulationDimension.Exceptional and uint64(firstInfo.gasUsed) == 3500
  elif mode in {ComputedStorageMode.Panic, ComputedStorageMode.CheckpointPanic}:
    assert firstInfo.termination == AccumulationTermination.Panic and firstInfo.dimension ==
        AccumulationDimension.Exceptional
  else:
    assert firstInfo.termination == AccumulationTermination.Halt and firstInfo.dimension ==
        AccumulationDimension.Regular
  storage(first.outcomeContext.value.effectAccounts.value, initialStorage(mode))
  let execution = completed(fixture)
  let actual = execution.assuredExecutionCompleted.value
  let info = actual.executionInfo.value
  assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
  assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == credit*2
  assert uint64(info.round.budget) == 1000000 and uint64(info.round.allowanceGas) == 0
  let inputs = actual.executionRound.value.roundProjection.value.roundInputs.value
  let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert uint32(service.service) == 42 and service.operands == 2 and service.transfers == 0
  assert uint64(service.gas) == credit*2
  let selected = actual.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let terminal = selected.outcomeInfo.value
  let expectedPanic = mode in {ComputedStorageMode.Panic, ComputedStorageMode.CheckpointPanic}
  if expectedPanic:
    assert terminal.termination == AccumulationTermination.Panic and terminal.dimension ==
        AccumulationDimension.Exceptional
  else:
    assert terminal.termination == AccumulationTermination.Halt and terminal.dimension ==
        AccumulationDimension.Regular
  assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
  assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
  assert uint64(info.gasUsed) > 0 and uint64(info.gasUsed) <= credit*2
  if mode in {ComputedStorageMode.OutOfGas, ComputedStorageMode.CheckpointOutOfGas}:
    assert uint64(info.gasUsed) > 4894 and uint64(info.gasUsed) <=
        5994 # Two literal2447 charges plus at most103 checkpoint and997 prepaid block gas fit7000.
    assert successorStorage(mode) != initialStorage(mode), "aggregation changes the selected storage oracle"
  let expected = successorStorage(mode)
  storage(selected.outcomeContext.value.effectAccounts.value, expected)
  let selfKeys = if expected.len == 0: 0 else: 1
  assert info.batch.selfWrites == selfKeys and info.batch.selfValueBytes == uint64(expected.len)
  let plan = composed(execution)
  let candidate = plan.assuredCompositionPlan.value.accumulationConsensusState.value
  storage(candidate, expected)
  assert uint32(metadata(candidate).lastAccumulation) == 3
  let balance = if mode == ComputedStorageMode.Underfunded: 49'u64 else: 50'u64
  assert uint64(metadata(candidate).balance) == balance
  assert array[32, byte](metadata(candidate).codeHash) == array[32, byte](metadata(
      original).codeHash)
  let queueConfig = assuredCompositionConfig().composition.ready.queues
  let history = decodeAccumulatedState(candidate.lookup(chapterKey(StateChapter(15))).value.bytes,
      queueConfig).value.snapshot
  assert history.accumulatedInfo.value.items == 3
  let ready = decodeReadyState(candidate.lookup(chapterKey(StateChapter(14))).value.bytes,
      queueConfig).value.snapshot
  assert ready.readyInfo.value.items == 0
  let activity = decodeActivityState(candidate.lookup(chapterKey(StateChapter(13))).value.bytes,
    ActivityConfig(cores: typeof(queueConfig.cores)(3), current: typeof(
        fixture.view.bestBlock.value.activeValidators)(9),
      previous: typeof(fixture.view.bestBlock.value.activeValidators)(6), maxServices: ElementLimit(
          4), maxBytes: ByteLimit(10000))).value.snapshot
  let counters = activity.serviceActivityAt(StatisticsServiceIndex(0)).value.statistics
  assert uint64(counters.counters[ServiceMeasure.RefinementCount]) == 0
  assert uint64(counters.counters[ServiceMeasure.AccumulationCount]) == 2
  assert uint64(counters.accumulationGas) == uint64(info.gasUsed)
  var state = fixture.state
  var view = fixture.view
  let published = advanceAssuredChain(state, view, plan)
  assert published.error == AssuredChainError.None
  let child = published.value.assuredChainBlock.value
  assert child.slot == 3 and view.retainedCount == 3 and view.finalizedBlock.value.slot == 1
  assert sameStateSnapshot(state.snapshot.value, candidate) and sameStateSnapshot(
      child.stateSnapshot, candidate)
  for field in low(Parameter)..high(Parameter):
    assert child.chainParameters.get(field) == execution.assuredExecutionParameters.value.get(
        field) # Original protocol tuple survives every outcome and canonical capture.
  storage(state.snapshot.value, expected)
  assert advanceAssuredChain(state, view, plan).error == AssuredChainError.StaleState
  assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, priorView)
  storage(original, initialStorage(mode))
  if expected.len > 0:
    var short = assuredExecutionConfig(fixture.queue)
    short.runner.completion.batch.selfValueBytes = ByteLimit(uint64(expected.len-1))
    let refused = executeAssuredAccumulation(fixture.queue, short)
    assert refused.error == AssuredExecutionError.RunnerFailure
    assert refused.runnerFailure.error == AccumulationRunnerError.CompletionFailure
    assert refused.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
    assert refused.runnerFailure.completionFailure.batchFailure.error ==
        AccumulationBatchError.LimitExceeded
    assert sameStateSnapshot(fixture.state.snapshot.value,
        original) # A real guest-byte refusal leaves the original canonical parent untouched.
  fixture

let modes = [ComputedStorageMode.Commit, ComputedStorageMode.Panic, ComputedStorageMode.Underfunded,
  ComputedStorageMode.CheckpointCommit, ComputedStorageMode.CheckpointPanic,
  ComputedStorageMode.OutOfGas, ComputedStorageMode.CheckpointOutOfGas]
var fixtures: seq[AssuredOutcomeFixture] = @[]
for mode in modes: fixtures.add(witness(mode)) # Every original mode is authored and computed independently before successor assurances.
proc cycle(fixtures: openArray[AssuredOutcomeFixture]) =
  ## Execute, stop, compose, publish and release all seven actual guest modes using retained genuine input sources.
  for fixture in fixtures:
    let source = composed(completed(fixture))
    var state = fixture.state
    var view = fixture.view
    let published = advanceAssuredChain(state, view, source)
    assert published.error == AssuredChainError.None and
        published.value.assuredChainBlock.value.slot == 3
cycle(fixtures)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixtures) # Seven actual guest executions plus all successor state phases retire per ownership cycle.
let after = getOccupiedMem()
assert before == after, "assured outcomes ARC release"
recordArcRelease("pvm_assured_outcomes", 1000, before, after)
echo "PVM assured outcomes passed"
echo "ARC_RELEASE cycles=1000 unchanged"
