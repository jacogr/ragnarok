# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc":"request_logical_continuation_arc_release"}

## Actual native request addition/removal/restoration and rollback continue from original identities with no supplied successor declarations; storage-only compatibility remains strict.
import std/assertions
import std/syncio
import std/envvars
import ../../support/app_collected_native_context
import ../../support/app_collected_logical_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/state_current_identity_context
import ../../support/app_download_chain
import ../../support/pvm_accumulation_program
import ../../support/testing_arc_evidence
import ../../../src/app/chain as app_chain
import ../../../src/app/candidate as app_candidate
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/state/logical_continuation as state_logical_continuation
import ../../../src/state/storage_logical_continuation as state_storage_logical_continuation
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_storage_history as state_accumulation_storage_history
import ../../../src/state/request_identity_history as state_request_identity_history
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual mandatory request namespace failures cannot masquerade as source or quota refusal.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## These selected early resource policies refuse before cryptographic work.
type Fixture = object ## Only real original logical parents and matching native producer updates enter tests.
  origin: CurrentNamespaceTransition
  update: PreparedCurrentChainUpdate
  hash: ServicePreimageHash
  length: RequestLength
proc candidatePolicy(requests = true): CurrentCandidateLimits =
  ## Independent producer host facts and final selected histories remain frozen through native input.
  result = currentCandidateLimits()
  result.completion.composition.validators.services = ElementLimit(2)
  result.storage = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
      facts: ElementLimit(16), bytes: ByteLimit(65536))
  if requests: result.requests = RequestIdentityHistoryLimits(entries: ElementLimit(8),
      outcomes: ElementLimit(16), facts: ElementLimit(16), bytes: ByteLimit(65536))
  result.completion.execution.initial.guests.storageFacts = AccumulationStorageFactLimits(
      items: ElementLimit(2), perKey: ByteLimit(2), totalKeyBytes: ByteLimit(2))
  result.completion.execution.execution.round.guests.storageFacts = result.completion.execution.initial.guests.storageFacts
  result.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  result.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
proc policy(): LogicalContinuationLimits =
  ## Existing storage policy is an exact compatibility alias of the common source/projection/qualification policy.
  let logical = namespaceLogicalLimits()
  LogicalContinuationLimits(identity: currentIdentityTestLimits, checks: ElementLimit(8192),
      scratchBytes: ByteLimit(262144), projection: namespaceRefreshLimits.projection,
      profile: logical.profile, globals: logical.globals, logical: logical.logical)
proc program(hash: ServicePreimageHash, length: RequestLength,
    operations: openArray[byte], checkpoint = false, panic = false): seq[byte] =
  ## Original digest bytes and real host operations enter parent code/signatures before execution; selected checkpoint/panic is genuine.
  let digest = array[32, byte](hash)
  var writable = newSeq[byte](32)
  for i in 0..<32: writable[i] = digest[i] # No caller-backed raw hash survives guest initialization.
  var instructions: seq[seq[byte]] = @[]
  for operation in operations:
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
        registerImmediate(9, uint64(uint32(length))), @[10'u8, operation]]:
      instructions.add(instruction) # Exact opcode boundaries remain owned by the authored guest envelope.
  if checkpoint: instructions.add(@[10'u8, 19])
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(octet)
proc prepare(origin: CurrentNamespaceTransition, requests = true): PreparedCurrentChainUpdate {.raises.} =
  ## Only matching actual collection/join releases native graph borrowing before any logical observation.
  var owner = initApplicationChain(origin.update.currentUpdatePriorView).value
  let admitted = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), origin.source.older, candidatePolicy(requests))
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  receipt.currentValue.value
proc fixture(kind: int): Fixture {.raises.} =
  ## Exact original identities, histories and programs are authored before complete roots/signatures; no map/result repair occurs.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  var hash = default(ServicePreimageHash)
  var length = RequestLength(17)
  if kind == 1:
    options.signed.serviceNamespaces[1].requests.add(StateRequestItem(hash: hash, length: length,
        history: requestedHistory()))
    options.secondProgram = program(hash, length, [
        26'u8]) # Remove a genuinely requested row with no associated preimage.
  elif kind == 2:
    let old = options.signed.serviceNamespaces[1].requests[1]
    hash = old.hash
    length = old.length
    options.signed.serviceNamespaces[1].requests[1].history = unavailableHistory(RequestSlot(1),
        RequestSlot(1))
    options.secondProgram = program(hash, length, [
        25'u8]) # Restore the real retained payload's existing request identity.
  elif kind == 3:
    options.secondProgram = program(hash, length, [25'u8, 26]) # Repeated identity touches end in genuine absence.
  elif kind == 4:
    options.secondProgram = program(hash, length, [25'u8], panic = true)
  elif kind == 5:
    options.secondProgram = program(hash, length, [25'u8], checkpoint = true, panic = true)
  else:
    options.secondProgram = program(hash, length, [25'u8]) # Introduce a new genuine request identity.
  let origin = namespaceTransitionFixture(nativeBase(), options)
  Fixture(origin: origin, update: prepare(origin), hash: hash, length: length)
proc check(fixture: Fixture, expected: bool): CurrentLogicalState =
  ## Producer raw identities alone choose new declarations; complete actual-map/current matching must reproduce the genuine source owner.
  let done = continueCurrentNamespaces(fixture.origin.parent, fixture.update, policy())
  assert done.error == LogicalContinuationError.None, $done.error
  let logical = done.value
  assert sameStateSnapshot(logical.currentLogicalInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value,
      fixture.update.currentUpdateState)
  let services = copySuppliedServices(logical.currentLogicalInventory.value,
      namespaceRefreshLimits.projection).value
  var found = false
  for service in services:
    for request in service.requests:
      if uint32(service.service) == 99 and array[32, byte](request.hash) == array[32, byte](
          fixture.hash) and uint32(request.length) == uint32(fixture.length): found = true
  assert found == expected
  logical
proc main() {.raises.} =
  let grown = fixture(0)
  let continued = check(grown, true)
  let legacy = continueCurrentStorage(grown.origin.parent, grown.update, policy())
  assert legacy.error == StorageContinuationError.StateFailure # The former storage-only contract must not silently broaden.
  discard check(fixture(1), false)
  let restored = fixture(2)
  let restoredLogical = check(restored, true)
  let copies = copySuppliedServices(restoredLogical.currentLogicalInventory.value,
      namespaceRefreshLimits.projection).value
  var sawRestoration = false
  for service in copies:
    for request in service.requests:
      if uint32(service.service) == 99 and array[32, byte](request.hash) == array[32, byte](
          restored.hash) and uint32(request.length) == uint32(restored.length):
        assert request.history.state == RequestState.Reavailable
        assert uint32(request.history.restoredAt) == restored.update.currentUpdateChildContext.slot
        sawRestoration = true
  assert sawRestoration
  discard check(fixture(3), false)
  discard check(fixture(4), false)
  discard check(fixture(5), true)
  let missing = prepare(grown.origin, requests = false)
  let refusedEvidence = continueCurrentNamespaces(grown.origin.parent, missing, policy())
  assert refusedEvidence.error == LogicalContinuationError.MissingRequestEvidence
  let crossed = continueCurrentNamespaces(restored.origin.parent, grown.update, policy())
  assert crossed.identityFailure.error == CurrentIdentityError.ParentMismatch
  fail(1)
  var short = policy()
  short.scratchBytes = ByteLimit(0)
  assert continueCurrentNamespaces(grown.origin.parent, grown.update, short).error ==
      LogicalContinuationError.LimitExceeded and calls() == 0
  short = policy()
  short.checks = ElementLimit(0)
  assert continueCurrentNamespaces(grown.origin.parent, grown.update, short).error ==
      LogicalContinuationError.LimitExceeded and calls() == 0
  short = policy()
  short.projection.bytes = ByteLimit(0)
  assert continueCurrentNamespaces(grown.origin.parent, grown.update, short).error ==
      LogicalContinuationError.LimitExceeded and calls() == 0
  let backend = continueCurrentNamespaces(grown.origin.parent, grown.update, policy())
  assert backend.requestError == RequestError.BackendFailure
  fail(0)
  short = policy()
  short.logical.rawKeyBytes = ByteLimit(0)
  assert continueCurrentNamespaces(grown.origin.parent, grown.update, short).error ==
      LogicalContinuationError.LogicalFailure
  var nextOwner = initApplicationChain(grown.update.currentUpdateView).value
  let child = signedChild(grown.update.currentUpdateChild)
  let receipt = collectNative(nextOwner, currentWire(child), [], candidatePolicy())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  let repeated = continueCurrentNamespaces(continued, receipt.currentValue.value, policy())
  assert repeated.error == LogicalContinuationError.None, $repeated.error
  assert sameStateSnapshot(repeated.value.currentLogicalUpdate.value.currentUpdatePriorState,
      grown.update.currentUpdateState)
  for i in 0..<25: discard continueCurrentNamespaces(grown.origin.parent, grown.update, policy()).value # Warm complete request reconstruction/current qualification.
  let before = getOccupiedMem()
  for i in 0..<1000: discard continueCurrentNamespaces(grown.origin.parent, grown.update, policy()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_request_logical_continuation", 1000, before, after)
  echo "request-logical-continuation: ok"
try:
  main()
except:
  quit(2) # Unexpected source/fixture refusal cannot count as successful continuation.
