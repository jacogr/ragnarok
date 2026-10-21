# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_storage_arc_release"}

## Actual guest storage effects survive computed execution, finalization and canonical chain publication only under the selected implication.

import std/[assertions, syncio]
import ../../../src/state/[computed_chain, computed_state_publication, computed_composition,
    computed_finalization, computed_execution, accumulation_runner, accumulation_execution,
    accumulation_batch,
    accumulation_provisions, accumulation_outcome, accumulation_context, accumulation_effects,
    accumulation_consensus, accumulation_finalization, store]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, assurances, state_layout, state_accounts, state_service_values, state_statistics]
import ../../support/[pvm_computed_storage_program, pvm_computed_execution, pvm_computed_chain,
    pvm_computed_state_publication, arc_evidence]

let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode canonical self-account metadata from the exact state at each maintained stage.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(89)).value.metadata
proc storage(state: StateStoreSnapshot, persists: bool) =
  ## Assert exact guest-memory bytes and independently derived footprint; a missing row differs from present-empty storage.
  let row = state.lookup(key)
  let account = metadata(state)
  if persists:
    assert row.error == StateStoreError.None
    assert row.value.bytes == @[21'u8, 22, 23]
    assert uint32(account.storageItems) == 1
    assert uint64(account.storageBytes) == 38
  else:
    assert row.error == StateStoreError.MissingKey
    assert uint32(account.storageItems) == 0
    assert uint64(account.storageBytes) == 0
proc witness(mode: ComputedStorageMode): ComposedComputedState =
  ## Run separately authored original programs, never inject a terminal observation or edit a completed source.
  let source = chainFixture(storage = mode)
  let parent = source.chainFixtureParent(source.chainFixtureParameters)
  assert parent.error == GenesisError.None
  let original = source.statePublicationParent
  assert sameStateSnapshot(parent.value.stateSnapshot, original)
  let balance = if mode == ComputedStorageMode.Underfunded: 49'u64 else: 50'u64
  assert uint64(metadata(original).balance) == balance
  storage(original, false)
  let initial = source.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionCompleted.value
  let outcome = initial.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let info = outcome.outcomeInfo.value
  let persists = mode == ComputedStorageMode.Commit
  if mode == ComputedStorageMode.Panic:
    assert info.termination == AccumulationTermination.Panic
    assert info.dimension == AccumulationDimension.Exceptional
  else:
    assert info.termination == AccumulationTermination.Halt
    assert info.dimension == AccumulationDimension.Regular
  assert uint64(info.gasUsed) >= 2447 and uint64(info.gasUsed) < 10000
  assert uint64(initial.executionInfo.value.gasUsed) == uint64(info.gasUsed)
  if mode == ComputedStorageMode.Commit:
    # Actual guest execution under insufficient local provenance/publication budgets must expose only precise refusals.
    let round = source.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value
    for policy in 0..2:
      var short = computedExecutionLimits()
      if policy >= 1: short.accountWriteKeys = ElementLimit(
          1) # Trace one real key; publication still has its independent zero default.
      if policy == 2:
        short.completion.batch.selfWrites = ElementLimit(1)
        short.completion.batch.selfValueBytes = ByteLimit(
            2) # Three actual guest bytes exceed the final copy ceiling by one.
      let refused = executeComputedAccumulation(round, short)
      assert refused.error == ComputedExecutionError.RunnerFailure
      let runner = refused.runnerFailure
      assert runner.error == AccumulationRunnerError.CompletionFailure
      assert runner.completionFailure.error == AccumulationExecutionError.BatchFailure
      let expected = if policy == 0: AccumulationBatchError.UnsupportedAccountEffects else: AccumulationBatchError.LimitExceeded
      assert runner.completionFailure.batchFailure.error == expected
      assert sameStateSnapshot(source.statePublicationParent, original)
      storage(original, false)
  storage(outcome.outcomeContext.value.effectAccounts.value, persists)
  let final = source.computedCompositionSource.value.computedFinalizationPlan.value
  storage(final.finalAccumulationState.value, persists)
  let composed = source.computedCompositionPlan.value.accumulationConsensusState.value
  storage(composed, persists)
  assert uint64(metadata(composed).balance) == balance
  assert uint32(metadata(composed).lastAccumulation) == 2
  assert array[32, byte](metadata(composed).codeHash) == array[32, byte](metadata(
      original).codeHash)
  assert uint64(metadata(composed).minimumAccumulationGas) == uint64(metadata(
      original).minimumAccumulationGas)
  assert uint64(metadata(composed).minimumTransferGas) == uint64(metadata(
      original).minimumTransferGas)
  let activity = decodeActivityState(composed.lookup(chapterKey(StateChapter(13))).value.bytes,
    ActivityConfig(cores: CoreCount(3), current: ValidatorCount(9), previous: ValidatorCount(6),
        maxServices: ElementLimit(4), maxBytes: ByteLimit(10000))).value.snapshot
  let service = activity.serviceActivityAt(StatisticsServiceIndex(0)).value
  assert uint32(service.service) == 42
  assert uint64(service.statistics.counters[ServiceMeasure.RefinementCount]) == 2
  assert uint64(service.statistics.counters[ServiceMeasure.AccumulationCount]) == 1
  assert uint64(service.statistics.accumulationGas) == uint64(info.gasUsed)
  var target = forkStateStore(original).value
  let alias = target
  var view = genesisView(parent).finalizeView(parent.value.blockHash).value
  let oldView = view
  let published = advanceComputedChain(target, view, source)
  assert published.error == ComputedChainError.None
  let child = published.value.computedChainBlock.value
  assert sameStateSnapshot(target.snapshot.value, composed)
  assert sameStateSnapshot(child.stateSnapshot, composed)
  assert sameStateSnapshot(published.value.computedChainPublication.value.computedPublishedSnapshot.value, composed)
  storage(target.snapshot.value, persists)
  storage(view.bestBlock.value.stateSnapshot, persists)
  assert uint64(view.bestBlock.value.activeValidators) == 9
  assert view.bestBlock.value.slot == 2 and view.retainedCount == 2
  assert array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](child.blockHash)
  assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](
      parent.value.blockHash)
  assert sameChainView(oldView, genesisView(parent).finalizeView(parent.value.blockHash).value)
  assert sameStateSnapshot(alias.snapshot.value, original)
  storage(alias.snapshot.value, false)
  assert uint32(metadata(original).lastAccumulation) == 0
  let pending = composed.lookup(chapterKey(StateChapter(10))).value.bytes
  assert pending.len > 0
  assert target.snapshot.value.lookup(chapterKey(StateChapter(10))).value.bytes == pending
  assert target.snapshot.value.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
  let selectedView = view
  assert advanceComputedChain(target, view, source).error == ComputedChainError.StaleState
  assert sameStateSnapshot(target.snapshot.value, composed)
  assert sameChainView(view, selectedView)
  source

let modes = [ComputedStorageMode.Commit, ComputedStorageMode.Panic, ComputedStorageMode.Underfunded]
var sources: seq[ComposedComputedState] = @[]
for mode in modes: sources.add(witness(mode)) # Each distinct original code/funding combination executes and normalizes genuinely.
proc detached(): AdvancedComputedChain =
  ## Keep an actual storage-bearing child alive after all local guest, source and live store/view handles retire.
  let source = chainFixture(storage = ComputedStorageMode.Commit)
  let parent = source.chainFixtureParent(source.chainFixtureParameters)
  var state = forkStateStore(source.statePublicationParent).value
  var view = genesisView(parent)
  advanceComputedChain(state, view, source).value
let held = detached()
storage(held.computedChainBlock.value.stateSnapshot, true)
proc cycle(sources: openArray[ComposedComputedState]) =
  ## Release private capture/header/index and view owners for all three genuine selected guest outcomes per cycle.
  for index, source in sources:
    let parent = source.chainFixtureParent(source.chainFixtureParameters)
    var state = forkStateStore(source.statePublicationParent).value
    var view = genesisView(parent)
    let receipt = advanceComputedChain(state, view, source).value
    storage(receipt.computedChainBlock.value.stateSnapshot, modes[index] ==
        ComputedStorageMode.Commit)
cycle(sources)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(sources) # Three real computed state versions survive while every per-publication owner retires.
let after = getOccupiedMem()
assert before == after, "computed storage ARC release"
recordArcRelease("pvm_computed_storage", 1000, before, after)
echo "PVM computed storage passed"
echo "ARC_RELEASE cycles=1000 unchanged"
