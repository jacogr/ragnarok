# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual native preparation freezes selected raw-storage history on its own update and refuses failed optional retention atomically.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_logical_context,
    current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context,
    accumulation_execution_context, accumulation_current_candidate_context, arc_evidence]
import ../../src/app/[chain, candidate, preparation_worker, current_block_input]
import ../../src/state/[accumulation_current_update, accumulation_storage_history,
    accumulation_effects, accumulation_round, accumulation_queue, report_admission,
    block_transition, block_admission, store]
import ../../src/codec/[bounded, state_layout]
import ../../src/chain/[provider, genesis]
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(CurrentChainPreparationResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.storageError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "history":
    discard default(PreparedCurrentChainUpdate).currentUpdateStorageHistory
    return
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(@[9'u8])
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let fixture = namespaceTransitionFixture(nativeBase(), options)
  assert not fixture.update.hasStorageHistory and not default(
      PreparedCurrentChainUpdate).hasStorageHistory
  var owner = initApplicationChain(fixture.update.currentUpdatePriorView).value
  let head = owner.chainView.bestBlock.value.blockHash
  let candidateBlock = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var limits = currentCandidateLimits()
  limits.storage = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
      facts: ElementLimit(16), bytes: ByteLimit(65536))
  let disabled = prepareCurrentCandidate(owner, candidateBlock, fixture.source.older, limits)
  assert disabled.error == CurrentCandidateError.PreparationFailure
  assert disabled.preparationFailure.storageError == StorageHistoryError.StorageFactsDisabled
  limits.completion.execution.initial.guests.storageFacts = AccumulationStorageFactLimits(
      items: ElementLimit(2), perKey: ByteLimit(1), totalKeyBytes: ByteLimit(2))
  limits.completion.execution.execution.round.guests.storageFacts = limits.completion.execution.initial.guests.storageFacts
  var short = limits
  short.storage.bytes = ByteLimit(0)
  let refused = prepareCurrentCandidate(owner, candidateBlock, fixture.source.older, short)
  assert refused.error == CurrentCandidateError.PreparationFailure
  assert refused.preparationFailure.storageError == StorageHistoryError.LimitExceeded
  let receipt = collectNative(owner, currentWire(candidateBlock), fixture.source.older, limits)
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted
  assert receipt.currentValue.error == CurrentBlockInputError.None
  let update = receipt.currentValue.value
  assert update.hasStorageHistory
  let history = update.currentUpdateStorageHistory
  let info = history.storageHistoryInfo.value
  assert info.facts == 1 and info.outcomes == 2
  let fact = history.storageHistoryAt(StorageHistoryIndex(0)).value.fact
  assert uint32(fact.storageFactInfo.value.service) == 99
  assert fact.copyStorageFactKey(ByteLimit(1)).value == @[7'u8]
  assert update.currentUpdateState.lookup(fact.storageFactInfo.value.key).value.bytes == @[9'u8]
  assert sameStateSnapshot(update.currentUpdatePriorState, fixture.update.currentUpdatePriorState)
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](head)
  var detached = fact.copyStorageFactKey(ByteLimit(1)).value
  detached[0] = 8
  assert fact.copyStorageFactKey(ByteLimit(1)).value == @[7'u8]
  for i in 0..<25: discard update.currentUpdateStorageHistory.storageHistoryInfo.value
  let before = getOccupiedMem()
  for i in 0..<1000: discard update.currentUpdateStorageHistory.storageHistoryInfo.value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("current_storage_provenance", 1000, before, after)
  echo "current-storage-provenance: ok"
try:
  main()
except:
  quit(2) # Genuine setup/execution refusal cannot impersonate guarded observation rejection.
