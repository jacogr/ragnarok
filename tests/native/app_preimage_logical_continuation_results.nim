# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine extrinsic/host preimage fulfillment and expired forget continue complete logical state from original or selected request hashes without supplied successor declarations.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/app_collected_native_context
import ../support/app_collected_logical_context
import ../support/state_current_namespace_transition_context
import ../support/state_current_namespace_execution_context
import ../support/state_current_namespace_context
import ../support/state_current_namespace_refresh_context
import ../support/state_accumulation_execution_context
import ../support/state_accumulation_current_candidate_context
import ../support/state_accumulation_current_chain_context
import ../support/state_current_identity_context
import ../support/pvm_accumulation_program
import ../support/testing_arc_evidence
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/state/logical_continuation as state_logical_continuation
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_storage_history as state_accumulation_storage_history
import ../../src/state/request_identity_history as state_request_identity_history
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_identities as state_current_identities
import ../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../src/state/supplied_services as state_supplied_services
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/composite as codec_composite
import ../../src/crypto/primitives as crypto_primitives
import ../../src/chain/parameters as chain_parameters
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Mandatory namespace derivation must preserve genuine backend refusal.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse the first preimage-key hash only after all original request derivations succeeded.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Planning ceilings refuse before any namespace hashes.
type Fixture = object ## Source descriptors contain only real original logical parents and matching native updates.
  origin: CurrentNamespaceTransition
  update: PreparedCurrentChainUpdate
  hash: ServicePreimageHash
  value: seq[byte]
proc candidatePolicy(): CurrentCandidateLimits =
  ## Original/selected request hashes and raw storage are frozen independently of complete output budgets.
  result = currentCandidateLimits()
  result.completion.composition.validators.services = ElementLimit(2)
  result.storage = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
      facts: ElementLimit(16), bytes: ByteLimit(65536))
  result.requests = RequestIdentityHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(
      16), facts: ElementLimit(16), bytes: ByteLimit(65536))
  result.completion.execution.initial.guests.storageFacts = AccumulationStorageFactLimits(
      items: ElementLimit(4), perKey: ByteLimit(8), totalKeyBytes: ByteLimit(32))
  result.completion.execution.execution.round.guests.storageFacts = result.completion.execution.initial.guests.storageFacts
  result.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  result.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
  result.completion.execution.initial.guests.provisions = AccumulationProvisionLimits(
      items: ElementLimit(4), perBlob: ByteLimit(32), totalBlobBytes: ByteLimit(128))
  result.completion.execution.execution.round.guests.provisions = result.completion.execution.initial.guests.provisions
  result.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(4),
      perBlob: ByteLimit(32), totalBlobBytes: ByteLimit(128))
  result.completion.execution.initial.provisions.encodedBytes = ByteLimit(256)
  result.completion.execution.execution.round.provisions = result.completion.execution.initial.provisions
proc policy(): LogicalContinuationLimits =
  ## Whole payload reconstruction remains separately bounded from original hash identity planning.
  let logical = namespaceLogicalLimits()
  LogicalContinuationLimits(identity: currentIdentityTestLimits, checks: ElementLimit(16384),
      scratchBytes: ByteLimit(262144), projection: namespaceRefreshLimits.projection,
      profile: logical.profile, globals: logical.globals, logical: logical.logical)
proc program(hash: ServicePreimageHash, blob: seq[byte], solicit = false, panic = false,
    checkpoint = false, forget = false, annul = false): seq[byte] =
  ## Authored full hash and payload enter actual guest memory; optional host paths use only real checked runtime operations.
  var memory = newSeq[byte](32+blob.len)
  for i, octet in array[32, byte](hash): memory[i] = octet
  for i, octet in blob: memory[32+i] = octet
  if annul:
    for i in 0..<32: memory[i] = 0 # A separate zero-hash/length17 request marks the junior for actual concurrent cancellation.
  var code: seq[seq[byte]] = @[]
  if solicit or forget or annul:
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
        registerImmediate(9, (if annul: 17'u64 else: uint64(blob.len))), @[10'u8, (
            if forget: 26'u8 else: 25'u8)]]:
      code.add(instruction) # Real original request facts precede any actual provision effect.
  if not forget:
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196640),
        registerImmediate(9, uint64(blob.len)), @[10'u8, 28]]:
      code.add(instruction) # Existing original request or the preceding real solicit authorizes fnprovide.
  if checkpoint: code.add(@[10'u8, 19]) # Actual checkpoint preserves selected request/removal changes across a later trap.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = memory): result.add(octet)
proc fixture(kind: int): Fixture {.raises.} =
  ## Complete original declarations and explicit profile/slot enter roots, signatures and snapshot binding before candidate execution.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.secondProgram = namespaceHaltCode()
  options.signed.serviceNamespaces = namespaceSeeds()
  var value = @[88'u8, 89, 90]
  if kind != 0: value = @[88'u8] # Host provision cases use one independently hashed writable byte.
  var hash = ServicePreimageHash(array[32, byte](blake2b256(value).value))
  var parameters = currentChainSettings()
  if kind == 5 or kind == 6:
    value = @[77'u8]
    hash = options.signed.serviceNamespaces[1].preimages[1].hash
    options.signed.serviceNamespaces[1].requests[1].history = unavailableHistory(RequestSlot(0),
        RequestSlot(1))
    var wire = encodeParameters(parameters)
    for i in 74..<78: wire[i] = 0 # Independently authored zero anchor age makes strict 4800-slot expiry reachable at a genuine signed slot5000.
    parameters = decodeParameters(wire).value
    options.signed.targetSlot = 5000
    options.secondProgram = program(hash, value, forget = true, panic = kind == 6)
  else:
    if kind != 3:
      options.signed.serviceNamespaces[1].requests.add(StateRequestItem(hash: hash,
          length: RequestLength(uint32(value.len)), history: requestedHistory()))
    if kind == 0:
      options.signed.preimageWire = @[1'u8, 99, 0, 0, 0, 3, 88, 89,
          90] # Exact independent tiny block-body encoding supplies the requested payload.
    else:
      options.secondProgram = program(hash, value, solicit = kind == 3, panic = kind in [2, 7],
          checkpoint = kind == 7, annul = kind == 4)
      if kind == 4:
        options.secondSupervisor = 42
        options.firstProgram = @[0'u8]
        for octet in guestEnvelope([registerImmediate(7, 99), registerImmediate(8, 196608),
            registerImmediate(9, 17), @[10'u8, 25], @[50'u8, 0]], writable = newSeq[byte](32)):
          options.firstProgram.add(octet) # Genuine supervisor and junior both modify99; original junior provision remains outside N.
  let origin = namespaceTransitionFixture(nativeBase(), options, policy = candidatePolicy(),
      parameters = parameters)
  var owner = initApplicationChain(origin.update.currentUpdatePriorView).value
  let admitted = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), origin.source.older, candidatePolicy())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  Fixture(origin: origin, update: receipt.currentValue.value, hash: hash, value: value)
proc check(source: Fixture, present: bool): CurrentLogicalState =
  ## Only whole actual-map and independent raw qualification grants a complete logical owner, including unchanged original preimage identities.
  let outcome = continueCurrentNamespaces(source.origin.parent, source.update, policy())
  if outcome.error != LogicalContinuationError.None:
    echo "preimage continuation refused: ", outcome.error # Preserve the actual stage for actionable native diagnostics.
  assert outcome.error == LogicalContinuationError.None
  let services = copySuppliedServices(outcome.value.currentLogicalInventory.value, policy().projection).value
  var found = false
  for service in services:
    for blob in service.preimages:
      if uint32(service.service) == 99 and array[32, byte](blob.hash) == array[32, byte](source.hash):
        assert blob.value == source.value
        found = true
  assert found == present
  assert sameStateSnapshot(outcome.value.currentLogicalUpdate.value.currentUpdateState,
      source.update.currentUpdateState)
  outcome.value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalContinuationResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.preimageError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let supplied = fixture(0)
  let current = check(supplied, true)
  let delivered = copySuppliedServices(current.currentLogicalInventory.value, policy().projection).value
  var available = false
  for service in delivered:
    for request in service.requests:
      if uint32(service.service) == 99 and array[32, byte](request.hash) == array[32, byte](supplied.hash):
        assert request.history.state == RequestState.Available and uint32(request.history.since) == 2
        available = true
  assert available
  let legacy = continueCurrentStorage(supplied.origin.parent, supplied.update, policy())
  assert legacy.error == LogicalContinuationError.StateFailure # Storage-only identity preservation cannot silently introduce a payload.
  discard check(fixture(1), true)
  discard check(fixture(2), false) # Panic selects the pre-provision exceptional context.
  discard check(fixture(7), true) # A real checkpoint retains the provision before the selected panic.
  discard check(fixture(3), true) # A genuine selected solicit supplies the original full hash for a newly fulfilled request.
  discard check(fixture(4), true) # GP533 preserves the cancelled junior's original provision while selected request mutations follow N.
  let expired = fixture(5)
  discard check(expired, false)
  assert expired.update.currentUpdateRequestHistory.requestIdentityHistoryAt(
      RequestIdentityHistoryIndex(0)).value.fact.removedPreimage
  discard check(fixture(6), true) # Panic without checkpoint rolls back expired forget and its removal authority together.
  let crossed = continueCurrentNamespaces(expired.origin.parent, supplied.update, policy())
  assert crossed.identityFailure.error == CurrentIdentityError.ParentMismatch
  fail(1)
  var short = policy()
  short.scratchBytes = ByteLimit(0)
  assert continueCurrentNamespaces(supplied.origin.parent, supplied.update, short).error ==
      LogicalContinuationError.LimitExceeded and calls() == 0
  short = policy()
  short.checks = ElementLimit(0)
  assert continueCurrentNamespaces(supplied.origin.parent, supplied.update, short).error ==
      LogicalContinuationError.LimitExceeded and calls() == 0
  fail(0)
  var requestCount = 0
  for service in supplied.origin.services: requestCount +=
      service.requests.len # Exact authored original request count fixes the independent backend failure boundary.
  failAfter(cint(requestCount))
  let namespaceFailure = continueCurrentNamespaces(supplied.origin.parent, supplied.update, policy())
  assert namespaceFailure.error == LogicalContinuationError.PreimageFailure
  assert namespaceFailure.preimageError == ServiceValueError.BackendFailure
  fail(0)
  short = policy()
  short.projection.perValue = ByteLimit(2)
  assert continueCurrentNamespaces(supplied.origin.parent, supplied.update, short).error ==
      LogicalContinuationError.LimitExceeded
  short = policy()
  short.logical.rawKeyBytes = ByteLimit(0)
  assert continueCurrentNamespaces(supplied.origin.parent, supplied.update, short).error ==
      LogicalContinuationError.LogicalFailure
  for i in 0..<25: discard continueCurrentNamespaces(supplied.origin.parent, supplied.update,
      policy()).value # Warm complete request-derived preimage planning and raw qualification.
  let before = getOccupiedMem()
  for i in 0..<1000: discard continueCurrentNamespaces(supplied.origin.parent, supplied.update,
      policy()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("preimage_logical_continuation", 1000, before, after)
  echo "preimage-logical-continuation: ok"
try:
  main()
except:
  quit(2) # Unexpected source/profile/native refusal cannot count as a successful logical continuation.
