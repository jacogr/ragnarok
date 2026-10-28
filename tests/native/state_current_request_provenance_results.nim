# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current native receipts retain only selected request identities, preserve exact producer history, and refuse disabled/short evidence atomically.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/app_collected_native_context
import ../support/app_collected_logical_context
import ../support/state_current_namespace_transition_context
import ../support/state_current_namespace_execution_context
import ../support/state_current_namespace_context
import ../support/state_accumulation_execution_context
import ../support/state_accumulation_current_candidate_context
import ../support/pvm_accumulation_program
import ../support/testing_arc_evidence
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/state/request_identity_history as state_request_identity_history
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_requests as codec_state_requests
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Pure selected history capture must remain available without cryptographic work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Complete descriptor admission precedes output allocation and requires no hashes.
const historyLimits = RequestIdentityHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(
    16), facts: ElementLimit(16), bytes: ByteLimit(65536))
proc requestCode(target: uint64): seq[byte] =
  ## Both genuine guests request the literal zero digest/length17 for junior99, with supervisor authority from the original parent.
  result = @[0'u8]
  let code = guestEnvelope([registerImmediate(7, target), registerImmediate(8, 196608),
      registerImmediate(9, 17), @[10'u8, 25], @[50'u8, 0]], writable = newSeq[byte](32))
  for octet in code: result.add(octet) # Existing current service framing owns the authored program.
proc origin(empty = false): CurrentNamespaceTransition {.raises.} =
  ## Original complete namespaces/code enter signatures before actual preparation; no completed result is forged.
  var options = executionFixtureConfig()
  options.firstProgram = if empty: namespaceHaltCode() else: requestCode(99)
  options.secondProgram = if empty: namespaceHaltCode() else: requestCode(high(uint64))
  options.secondSupervisor = 42
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  namespaceTransitionFixture(nativeBase(), options)
proc candidatePolicy(): CurrentCandidateLimits =
  ## Original host request capture and complete selected retention are independently frozen on the native input.
  result = currentCandidateLimits()
  result.requests = historyLimits
  result.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  result.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
proc capture(source: CurrentNamespaceTransition): PreparedCurrentChainUpdate {.raises.} =
  ## Matching collection and joined shutdown retire the fixed-address worker lease before any captured history alias is read.
  var owner = initApplicationChain(source.update.currentUpdatePriorView).value
  let admitted = source.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), source.source.older, candidatePolicy())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  let update = receipt.currentValue.value
  assert sameStateSnapshot(update.currentUpdatePriorState, source.update.currentUpdatePriorState)
  assert not sameStateSnapshot(update.currentUpdateState,
      owner.chainView.bestBlock.value.stateSnapshot)
  update
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(CurrentChainPreparationResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.requestHistoryError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "history":
    discard default(PreparedCurrentChainUpdate).currentUpdateRequestHistory
    return
  if mode == "capture":
    let absentCapture = default(RequestIdentityHistoryResult[RequestIdentityHistory])
    discard absentCapture.value
    return
  let source = origin()
  assert not source.update.hasRequestHistory
  let update = capture(source)
  assert update.hasRequestHistory and not update.hasStorageHistory
  let history = update.currentUpdateRequestHistory
  let info = history.requestIdentityHistoryInfo.value
  assert info.entries == 1 and info.outcomes == 2 and info.facts == 1
  assert info.bytes == uint64(sizeof(RequestIdentityHistoryRow))
  let row = history.requestIdentityHistoryAt(RequestIdentityHistoryIndex(0)).value
  assert uint32(row.fact.service) == 99 and uint32(row.fact.length) == 17
  assert array[32, byte](row.fact.hash) == default(array[32, byte]) and not row.fact.removedPreimage
  assert update.currentUpdateState.lookup(row.fact.key).value.bytes == @[0'u8]
  let completed = history.requestIdentityHistorySource.value
  let selected = completed.completedSequenceSource.value.currentSequenceCoverageAt(
      CurrentSequenceEntryIndex(0)).value.coverageAnnulment.value
  assert selected.annulmentInfo.value.annulled == 1
  assert selected.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(
      1)).value.outcomeContext.value.effectRequestFactCount.value == 1
  assert selected.annulmentSelectedRequestFactCountAt(AccumulationAnnulmentIndex(1)).value == 0
  assert selected.annulmentSelectedRequestFactAt(AccumulationAnnulmentIndex(1),
      AccumulationRequestFactIndex(0)).error == AccumulationAnnulmentError.InvalidIndex
  var detached = row
  detached.fact.length = RequestLength(3)
  assert uint32(history.requestIdentityHistoryAt(RequestIdentityHistoryIndex(
      0)).value.fact.length) == 17
  var owner = initApplicationChain(source.update.currentUpdatePriorView).value
  let admitted = source.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var short = candidatePolicy()
  short.completion.execution.initial.guests.requestFacts = ElementLimit(0)
  let disabled = prepareCurrentCandidate(owner, admitted, source.source.older, short)
  assert disabled.error == CurrentCandidateError.PreparationFailure
  assert disabled.preparationFailure.requestHistoryError ==
      RequestIdentityHistoryError.RequestFactsDisabled
  short = candidatePolicy()
  short.requests.bytes = ByteLimit(0)
  let refused = prepareCurrentCandidate(owner, admitted, source.source.older, short)
  assert refused.error == CurrentCandidateError.PreparationFailure
  assert refused.preparationFailure.requestHistoryError == RequestIdentityHistoryError.LimitExceeded
  let enabledEmpty = capture(origin(empty = true))
  assert enabledEmpty.hasRequestHistory and enabledEmpty.currentUpdateRequestHistory.requestIdentityHistoryInfo.value.facts == 0
  fail(1)
  assert captureRequestIdentityHistory(completed, historyLimits).value.requestIdentityHistoryInfo.value.facts == 1
  var limited = historyLimits
  limited.entries = ElementLimit(0)
  assert captureRequestIdentityHistory(completed, limited).error ==
      RequestIdentityHistoryError.LimitExceeded
  limited = historyLimits
  limited.outcomes = ElementLimit(1)
  assert captureRequestIdentityHistory(completed, limited).error ==
      RequestIdentityHistoryError.LimitExceeded
  limited = historyLimits
  limited.facts = ElementLimit(0)
  assert captureRequestIdentityHistory(completed, limited).error ==
      RequestIdentityHistoryError.LimitExceeded
  limited = historyLimits
  limited.bytes = ByteLimit(info.bytes-1)
  assert captureRequestIdentityHistory(completed, limited).error ==
      RequestIdentityHistoryError.LimitExceeded
  limited.bytes = ByteLimit(info.bytes)
  assert captureRequestIdentityHistory(completed, limited).value.requestIdentityHistoryInfo.value.bytes == info.bytes
  assert calls() == 0
  assert history.requestIdentityHistoryAt(RequestIdentityHistoryIndex(high(uint64))).error ==
      RequestIdentityHistoryError.InvalidIndex
  fail(0)
  for i in 0..<25: discard captureRequestIdentityHistory(completed,
      historyLimits).value # Warm exact isolated history retention and release.
  let before = getOccupiedMem()
  for i in 0..<1000: discard captureRequestIdentityHistory(completed, historyLimits).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("current_request_provenance", 1000, before, after)
  echo "current-request-provenance: ok"
try:
  main()
except:
  quit(2) # Unexpected preparation/fixture refusal cannot impersonate guarded history access.
