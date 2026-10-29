# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_fetch_tail_arc_release"}

## Actual guest arithmetic derives a clipped tail and persists its byte plus the full returned length through canonical publication.

import std/[assertions, syncio]
import ../../../src/state/assured/[chain as assured_chain, composition as assured_composition,
    execution as assured_execution, queue as assured_queue]
import ../../../src/state/accumulation/[execution as accumulation_execution,
    round as accumulation_round, inputs as accumulation_inputs, batch as accumulation_batch,
    provisions as accumulation_provisions, outcome as accumulation_outcome,
    context as accumulation_context, effects as accumulation_effects,
    consensus as accumulation_consensus, runner as accumulation_runner,
    dispatch as accumulation_dispatch]
import ../../../src/state/store
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, c2_records]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values, statistics as state_statistics,
    workqueues as state_workqueues]
import ../../../src/pvm/[machine, step]
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc configFor(queue: AssuredAccumulationQueue): AssuredExecutionConfig =
  ## Bound exactly one eleven-byte guest value while retaining all original protocol and independent engine controls.
  result = assuredExecutionConfig(queue)
  result.runner.completion.batch.selfValueBytes = ByteLimit(11)
proc expectedBytes(completed: CompletedBlockAccumulation, config: AssuredExecutionConfig): seq[byte] =
  ## Canonical C.2 ends with raw auth trace or its empty count; derive this independently of observed guest memory/return registers.
  let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  let owner = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(
      0)).value.operand
  let info = owner.operandInfo.value
  let measured = ownedOperandSize(owner, config.runner.fetch.operand)
  assert measured.error == RecordError.None and measured.value > 3 and measured.value <= 4000
  assert measured.value == info.consumed
  assert info.authBytes >= 0 and info.authBytes <= 1000
  var trace = newSeq[byte](info.authBytes)
  let copied = owner.copyOperandTrace(trace)
  assert copied.error == RecordError.None and copied.value == info.authBytes
  let tail = if trace.len == 0: 0'u8 else: trace[trace.len-1]
  assert tail != 21, "fixed input must distinguish one-byte copy from unchanged RW"
  result = @[tail, 22'u8, 23]
  let length = uint64(measured.value)
  for index in 0..<8:
    result.add(byte((length shr (8*index)) and 255)) # Eight bounded shifts retain the complete canonical length, never the clipped copied count1.
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Inspect exact account fields from each retained canonical full-map owner.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, expected: openArray[byte]) =
  ## Exactly one tail byte changes while the following two RW bytes survive and all eight return bytes are stored.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @expected
  assert expected.len == 11 and expected[1] == 22 and expected[2] == 23
  let account = metadata(state)
  assert uint32(account.storageItems) == 1 and uint64(account.storageBytes) == 46
  assert uint64(account.balance) == 58
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Execute both genuine host fetches, arithmetic and storage under the actual retained input/parameter authority.
  let outcome = executeAssuredAccumulation(fixture.queue, configFor(fixture.queue))
  if outcome.error != AssuredExecutionError.None:
    echo "fetch-tail execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Certify real termination and full state composition without replaying initial guest work.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None: echo "fetch-tail composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
let fixture = assuredOutcomeFixture(ComputedStorageMode.FetchTail)
let config = configFor(fixture.queue)
let original = fixture.state.snapshot.value
let oldView = fixture.view
let expectedFirst = expectedBytes(fixture.first, config)
storage(original, expectedFirst)
assert uint32(metadata(original).lastAccumulation) == 2
let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
storage(first.outcomeContext.value.effectAccounts.value, expectedFirst)
let source = execute(fixture)
let completed = source.assuredExecutionCompleted.value
let expected = expectedBytes(completed, config)
let info = completed.executionInfo.value
assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
assert info.batch.selfWrites == 1 and info.batch.selfValueBytes == 11
assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
assert uint64(info.gasUsed) > 3161 and uint64(info.gasUsed) <= 4158
let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
let terminal = selected.outcomeInfo.value
assert terminal.termination == AccumulationTermination.Halt and terminal.dimension ==
    AccumulationDimension.Regular
assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
storage(selected.outcomeContext.value.effectAccounts.value, expected)
var short = config
short.runner.calls = HostCallLimit(2)
let calls = executeAssuredAccumulation(fixture.queue, short)
assert calls.error == AssuredExecutionError.RunnerFailure
assert calls.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert calls.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
assert calls.runnerFailure.dispatchFailure.executionError == StepError.HostCallLimitExceeded
short = config
short.runner.copyBytes = MemoryByteLimit(11)
assert executeAssuredAccumulation(fixture.queue, short).error == AssuredExecutionError.None
short.runner.copyBytes = MemoryByteLimit(10)
let copy = executeAssuredAccumulation(fixture.queue, short)
assert copy.error == AssuredExecutionError.RunnerFailure
assert copy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert copy.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
short = config
short.runner.completion.batch.selfValueBytes = ByteLimit(10)
let effects = executeAssuredAccumulation(fixture.queue, short)
assert effects.error == AssuredExecutionError.RunnerFailure
assert effects.runnerFailure.error == AccumulationRunnerError.CompletionFailure
assert effects.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
assert effects.runnerFailure.completionFailure.batchFailure.error ==
    AccumulationBatchError.LimitExceeded
let composed = compose(source)
let candidate = composed.assuredCompositionPlan.value.accumulationConsensusState.value
storage(candidate, expected)
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
storage(published.value.assuredChainSnapshot.value, expected)
for field in low(Parameter)..high(Parameter):
  assert published.value.assuredChainBlock.value.chainParameters.get(field) ==
      source.assuredExecutionParameters.value.get(
      field) # Actual returned-length use cannot replace original protocol parameters.
assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
storage(original, expectedFirst)
proc cycle(fixture: AssuredOutcomeFixture) =
  ## Execute real query/arithmetic/clipped-copy/store, compose and publish one actual successor then release every owner.
  let source = compose(execute(fixture))
  var state = fixture.state
  var view = fixture.view
  let result = advanceAssuredChain(state, view, source)
  assert result.error == AssuredChainError.None
cycle(fixture)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixture) # Full dynamic guest dataflow and all private/public state phases retire each cycle.
let after = getOccupiedMem()
assert before == after, "assured fetch tail ARC release"
recordArcRelease("pvm_assured_fetch_tail", 1000, before, after)
echo "PVM assured fetch tail passed"
echo "ARC_RELEASE cycles=1000 unchanged"
