# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual native receipts freeze selected creation/ejection identities, retain cancelled originals separately, and refuse incomplete capture without adopting a private candidate.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_logical_context,
  current_namespace_transition_context, current_namespace_execution_context,
  current_namespace_context, accumulation_execution_context,
  accumulation_current_candidate_context, pvm_accumulation_program, arc_evidence]
import ../../src/app/[chain, candidate, preparation_worker, current_block_input]
import ../../src/state/[service_identity_history, accumulation_current_update,
  accumulation_effects, accumulation_annulment, accumulation_current_driver,
  accumulation_current_sequence, accumulation_coverage, accumulation_outcome,
  accumulation_round, accumulation_queue, report_admission, block_transition,
  block_admission, store]
import ../../src/codec/[bounded, state_layout, state_accounts]
import ../../src/chain/[provider, genesis]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fixed history capture admits its complete output without cryptographic work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Quotas and immutable row projection never invoke a hash.
const historyLimits = ServiceIdentityHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
  creations: ElementLimit(16), deletions: ElementLimit(16), bytes: ByteLimit(65536))
proc creationCode(checkpoint = false, panic = false): seq[byte] =
  ## A genuine zero-deposit automatic new seeds an exact one-byte code request; optional checkpoint selects its actual retained lineage.
  var payload = newSeq[byte](60)
  payload[32] = 1
  var code = @[registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20]]
  if checkpoint: code.add(@[10'u8, 19]) # Real host checkpoint retains the creation before a later trap.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc supervisorCode(): seq[byte] =
  ## Supervisor42 modifies junior99 while the genuine concurrent junior creates, so only the latter's original membership is cancelled.
  result = @[0'u8]
  for octet in guestEnvelope([registerImmediate(7, 99), registerImmediate(8, 196608),
      registerImmediate(9, 17), @[10'u8, 25], @[50'u8, 0]], writable = newSeq[byte](32)):
    result.add(octet)
proc origin(eject = false, annul = false, checkpoint = false, panic = false,
    halt = false): CurrentNamespaceTransition {.raises.} =
  ## Complete original code and raw namespaces enter roots and signatures before genuine current preparation.
  var options = executionFixtureConfig()
  options.firstProgram = if halt: namespaceHaltCode() elif eject: namespaceEjectCode()
    elif annul: supervisorCode() else: creationCode(checkpoint, panic)
  options.secondProgram = if annul: creationCode() else: namespaceHaltCode()
  options.secondSupervisor = 42
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  if eject:
    options.second = ExecutionEnding.Missing # No orphan raw namespaces or participating target mutation exists.
    options.secondBalance = 0
    options.signed.serviceNamespaces[1].storage = @[]
    options.signed.serviceNamespaces[1].preimages = @[]
    options.signed.serviceNamespaces[1].requests = @[]
  var policy = currentCandidateLimits()
  policy.completion.composition.validators.services = ElementLimit(4)
  namespaceTransitionFixture(nativeBase(), options, ElementLimit(4), policy)
proc candidatePolicy(): CurrentCandidateLimits =
  ## Freeze independent producer membership quotas and final selected history retention on actual native inputs.
  result = currentCandidateLimits()
  result.serviceIdentities = historyLimits
  result.completion.composition.validators.services = ElementLimit(4)
  result.completion.execution.initial.guests.deletedAccounts = ElementLimit(4)
  result.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(4)
proc capture(source: CurrentNamespaceTransition): PreparedCurrentChainUpdate {.raises.} =
  ## Join the native worker before inspecting immutable evidence; collection alone never adopts its staged candidate.
  var owner = initApplicationChain(source.update.currentUpdatePriorView).value
  let admitted = source.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), source.source.older, candidatePolicy())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted
  assert receipt.currentValue.error == CurrentBlockInputError.None
  let update = receipt.currentValue.value
  assert sameStateSnapshot(update.currentUpdatePriorState,
      owner.chainView.bestBlock.value.stateSnapshot)
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
    discard empty.serviceHistoryError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "effect-count":
    discard default(AccumulationEffectContext).effectDeletedAccountFactCount.value
    return
  if mode == "effect-fact":
    discard default(AccumulationEffectContext).effectDeletedAccountFactAt(
        AccumulationDeletedAccountIndex(0)).value
    return
  if mode == "history":
    discard default(PreparedCurrentChainUpdate).currentUpdateServiceIdentityHistory
    return
  if mode == "capture":
    let absent = default(ServiceIdentityHistoryResult[ServiceIdentityHistory])
    discard absent.value
    return
  let source = origin()
  assert not source.update.hasServiceIdentityHistory
  let update = capture(source)
  assert update.hasServiceIdentityHistory and not update.hasRequestHistory and
      not update.hasStorageHistory
  let history = update.currentUpdateServiceIdentityHistory
  let info = history.serviceIdentityHistoryInfo.value
  assert info.entries == 1 and info.outcomes == 2 and info.creations == 1 and info.deletions == 0
  assert info.bytes == uint64(sizeof(ServiceCreationRow))
  let row = history.serviceIdentityCreationAt(ServiceCreationIndex(0)).value
  assert update.currentUpdateState.lookup(chapterServiceKey(StateChapter(255),
      row.fact.service)).error == StateStoreError.None
  assert update.currentUpdateState.lookup(row.fact.requestKey).value.bytes == @[0'u8]
  var detached = row
  detached.fact.service = ServiceIndex(1)
  assert uint32(history.serviceIdentityCreationAt(ServiceCreationIndex(0)).value.fact.service) != 1
  let removed = capture(origin(eject = true))
  let deletion = removed.currentUpdateServiceIdentityHistory
  let deleted = deletion.serviceIdentityDeletionAt(ServiceDeletionIndex(0)).value
  assert uint32(deleted.fact.service) == 99
  assert deletion.serviceIdentityHistoryInfo.value.deletions == 1
  assert removed.currentUpdateState.lookup(chapterServiceKey(StateChapter(255),
      deleted.fact.service)).error == StateStoreError.MissingKey
  let cancelled = capture(origin(annul = true)).currentUpdateServiceIdentityHistory
  assert cancelled.serviceIdentityHistoryInfo.value.creations == 0
  let selected = cancelled.serviceIdentityHistorySource.value.completedSequenceSource.value.currentSequenceCoverageAt(
      CurrentSequenceEntryIndex(0)).value.coverageAnnulment.value
  assert selected.annulmentInfo.value.annulled == 1
  assert selected.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(
      1)).value.outcomeContext.value.effectCreatedAccountFactCount.value == 1
  assert selected.annulmentSelectedCreatedAccountFactCountAt(AccumulationAnnulmentIndex(1)).value == 0
  assert selected.annulmentSelectedCreatedAccountFactAt(AccumulationAnnulmentIndex(1),
      AccumulationCreatedAccountIndex(0)).error == AccumulationAnnulmentError.InvalidIndex
  for checkpoint in [false, true]:
    # Actual terminal selection, rather than the original regular trace, determines retained creation membership.
    let selectedHistory = capture(origin(checkpoint = checkpoint,
        panic = true)).currentUpdateServiceIdentityHistory
    assert selectedHistory.serviceIdentityHistoryInfo.value.creations == (if checkpoint: 1 else: 0)
  assert capture(origin(halt = true)).currentUpdateServiceIdentityHistory.serviceIdentityHistoryInfo.value.creations == 0
  var owner = initApplicationChain(source.update.currentUpdatePriorView).value
  let admitted = source.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var limited = candidatePolicy()
  limited.completion.execution.initial.guests.deletedAccounts = ElementLimit(0)
  let disabled = prepareCurrentCandidate(owner, admitted, source.source.older, limited)
  assert disabled.error == CurrentCandidateError.PreparationFailure
  assert disabled.preparationFailure.serviceHistoryError ==
      ServiceIdentityHistoryError.DeletedAccountsDisabled
  limited = candidatePolicy()
  limited.completion.execution.initial.guests.createdAccounts = ElementLimit(0)
  let quiet = origin(halt = true)
  let quietOwner = initApplicationChain(quiet.update.currentUpdatePriorView).value
  let quietBlock = quiet.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let noCreations = prepareCurrentCandidate(quietOwner, quietBlock, quiet.source.older, limited)
  assert noCreations.error == CurrentCandidateError.CompletionFailure # Existing current account composition requires enabled creation capture, even for empty membership.
  limited = candidatePolicy()
  limited.serviceIdentities.bytes = ByteLimit(0)
  let refused = prepareCurrentCandidate(owner, admitted, source.source.older, limited)
  assert refused.error == CurrentCandidateError.PreparationFailure
  assert refused.preparationFailure.serviceHistoryError == ServiceIdentityHistoryError.LimitExceeded
  assert sameStateSnapshot(owner.chainView.bestBlock.value.stateSnapshot,
      update.currentUpdatePriorState)
  let completed = history.serviceIdentityHistorySource.value
  fail(1)
  for kind in 0..<5:
    # Independent original coverage, creation/deletion and native-byte policies reject before output arrays or hashing.
    var short = historyLimits
    case kind
    of 0: short.entries = ElementLimit(0) # No original entry extent is silently truncated.
    of 1: short.outcomes = ElementLimit(1) # Both original invocations count even if later cancelled.
    of 2: short.creations = ElementLimit(0) # Complete selected creation extent is admitted first.
    of 3: short.bytes = ByteLimit(info.bytes-1) # Descriptor bytes have a separate exact boundary.
    else: short.deletions = ElementLimit(0) # Nonempty genuine deletion requires its own extent.
    let result = captureServiceIdentityHistory(if kind ==
        4: deletion.serviceIdentityHistorySource.value else: completed, short)
    assert result.error == ServiceIdentityHistoryError.LimitExceeded
  var exact = historyLimits
  exact.bytes = ByteLimit(info.bytes)
  assert captureServiceIdentityHistory(completed, exact).value.serviceIdentityHistoryInfo.value.bytes == info.bytes
  assert calls() == 0
  assert history.serviceIdentityCreationAt(ServiceCreationIndex(high(uint64))).error ==
      ServiceIdentityHistoryError.InvalidIndex
  assert history.serviceIdentityDeletionAt(ServiceDeletionIndex(0)).error ==
      ServiceIdentityHistoryError.InvalidIndex
  assert default(ServiceIdentityHistory).serviceIdentityHistoryInfo.error ==
      ServiceIdentityHistoryError.InvalidSource
  fail(0)
  for i in 0..<25: discard captureServiceIdentityHistory(completed,
      historyLimits).value # Warm this exact immutable producer graph retention/release.
  let before = getOccupiedMem()
  for i in 0..<1000: discard captureServiceIdentityHistory(completed, historyLimits).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("current_service_provenance", 1000, before, after)
  echo "current-service-provenance: ok"
try:
  main()
except:
  quit(2) # Fixture or preparation failure cannot impersonate a runtime guard verdict.
