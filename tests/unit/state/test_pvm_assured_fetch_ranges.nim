# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_fetch_ranges_arc_release"}

## Real full-width guest fetches preserve zero-copy memory and persist all returned length/NONE bytes through canonical publication.

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
import ../../../src/pvm/machine
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Inspect actual canonical account fields at each full-state owner.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc rangeConfig(queue: AssuredAccumulationQueue): AssuredExecutionConfig =
  ## Authorize exactly the eleven real final bytes; original parameters and all other independent execution ceilings stay inherited.
  result = assuredExecutionConfig(queue)
  result.runner.completion.batch.selfValueBytes = ByteLimit(11)
proc expectedBytes(completed: CompletedBlockAccumulation, mode: ComputedStorageMode,
    config: AssuredExecutionConfig): seq[byte] =
  ## Independently encode full LE64 canonical record length or NONE, preceded by the untouched original RW prefix.
  var word = high(uint64)
  if mode == ComputedStorageMode.FetchWideOffset:
    let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
    let first = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(0)).value
    let measured = ownedOperandSize(first.operand, config.runner.fetch.operand)
    assert measured.error == RecordError.None and measured.value > 3 and measured.value <= 4000
    word = uint64(measured.value) # This length comes from the actual canonical source, never the guest's observed return register.
  result = @[21'u8, 22, 23]
  for index in 0..<8:
    result.add(byte((word shr (8*index)) and 255)) # Eight shifts at most56 preserve the entire unsigned return word without narrowing.
proc storage(state: StateStoreSnapshot, expected: openArray[byte]) =
  ## Prefix preservation distinguishes true zero-copy clipping from a narrowed offset or index that would read the first record.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @expected
  assert expected.len == 11 and expected[0] == 21 and expected[1] == 22 and expected[2] == 23
  let account = metadata(state)
  assert uint32(account.storageItems) == 1 and uint64(account.storageBytes) == 46
  assert uint64(account.balance) == 58
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Run the actual full-width instructions and real store_u64 before any storage/outcome certificate is observed.
  let outcome = executeAssuredAccumulation(fixture.queue, rangeConfig(fixture.queue))
  if outcome.error != AssuredExecutionError.None:
    echo "fetch-range execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Drive genuine completed input work to terminal history and all maintained state phases without replay.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None: echo "fetch-range composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
proc witness(mode: ComputedStorageMode): AssuredOutcomeFixture =
  ## Compare actual original and successor full return words, proving distinct present-empty and absent behavior through publication.
  let fixture = assuredOutcomeFixture(mode)
  let config = rangeConfig(fixture.queue)
  let original = fixture.state.snapshot.value
  let oldView = fixture.view
  let firstExpected = expectedBytes(fixture.first, mode, config)
  storage(original, firstExpected)
  assert uint32(metadata(original).lastAccumulation) == 2
  let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
  assert first.outcomeInfo.value.dimension == AccumulationDimension.Regular
  storage(first.outcomeContext.value.effectAccounts.value, firstExpected)
  let source = execute(fixture)
  let completed = source.assuredExecutionCompleted.value
  let expected = expectedBytes(completed, mode, config)
  let info = completed.executionInfo.value
  assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
  assert info.batch.selfWrites == 1 and info.batch.selfValueBytes == 11
  assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
  assert uint64(info.gasUsed) > 2806 and uint64(info.gasUsed) <= 3803
  let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  assert inputs.invocationServiceAt(InvocationServiceIndex(0)).value.operands == 2
  let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let terminal = selected.outcomeInfo.value
  assert terminal.termination == AccumulationTermination.Halt and terminal.dimension ==
      AccumulationDimension.Regular
  assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
  assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
  storage(selected.outcomeContext.value.effectAccounts.value, expected)
  if mode == ComputedStorageMode.FetchWideIndex:
    for index in 3..<11: assert expected[index] ==
        255 # Persisted NONE is all eight0xff bytes, not a truncated length or fabricated empty success.
  else:
    assert expected[10] == 0 and expected[3] != 255 # A complete small canonical record length remains distinguishable from NONE.
  var short = config
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
  assert array[32, byte](metadata(candidate).codeHash) == array[32, byte](metadata(
      original).codeHash)
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
        field) # Original funding/capture descriptions do not replace protocol authority.
  assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
  storage(original, firstExpected)
  fixture

let modes = [ComputedStorageMode.FetchWideOffset, ComputedStorageMode.FetchWideIndex]
var fixtures: seq[AssuredOutcomeFixture] = @[]
for mode in modes: fixtures.add(witness(mode)) # Both genuinely authored programmes exercise low32-zero natural values before any result is observed.
proc cycle(fixtures: openArray[AssuredOutcomeFixture]) =
  ## Execute actual full-width fetch/store instructions, compose and publish both outcomes, then release every successor owner.
  for fixture in fixtures:
    let source = compose(execute(fixture))
    var state = fixture.state
    var view = fixture.view
    let published = advanceAssuredChain(state, view, source)
    assert published.error == AssuredChainError.None
cycle(fixtures)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixtures) # Two real full-width guest executions plus complete state phases and capture retire each cycle.
let after = getOccupiedMem()
assert before == after, "assured fetch ranges ARC release"
recordArcRelease("pvm_assured_fetch_ranges", 1000, before, after)
echo "PVM assured fetch ranges passed"
echo "ARC_RELEASE cycles=1000 unchanged"
