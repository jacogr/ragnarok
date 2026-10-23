# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc":"service_logical_continuation_arc_release"}

## Real native service creation/ejection continues complete logical state without supplied successor declarations, while missing evidence and unsupported generations remain closed.
import std/[assertions, syncio, envvars]
import ../../support/[collected_native_context, collected_logical_context,
  current_namespace_transition_context, current_namespace_execution_context,
  current_namespace_context, current_namespace_refresh_context,
  accumulation_execution_context, accumulation_current_candidate_context,
  current_identity_context, application_download_chain, pvm_accumulation_program, arc_evidence]
import ../../../src/app/[chain, candidate, preparation_worker, current_block_input]
import ../../../src/state/[logical_continuation, service_identity_history,
  accumulation_current_update, accumulation_storage_history, request_identity_history,
  accumulation_effects, accumulation_round, accumulation_queue, report_admission,
  block_transition, block_admission, current_logical, current_identities,
  supplied_logical_inventory, supplied_services, store]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_requests]
import ../../../src/chain/[provider, genesis]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Early planning ceilings must refuse independently of crypto availability.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Exact whole service/resource preflight cannot spend a request hash first.
type Fixture = object ## Only genuine original parents and matching worker-collected successors feed continuation.
  origin: CurrentNamespaceTransition
  update: PreparedCurrentChainUpdate
proc candidatePolicy(members = true): CurrentCandidateLimits =
  ## Independent host raw identities and all selected histories are frozen before actual guest execution.
  result = currentCandidateLimits()
  result.completion.composition.validators.services = ElementLimit(4)
  result.storage = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
      facts: ElementLimit(16), bytes: ByteLimit(65536))
  result.requests = RequestIdentityHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(
      16), facts: ElementLimit(16), bytes: ByteLimit(65536))
  if members:
    result.serviceIdentities = ServiceIdentityHistoryLimits(entries: ElementLimit(8),
        outcomes: ElementLimit(16), creations: ElementLimit(16), deletions: ElementLimit(16),
        bytes: ByteLimit(65536))
  result.completion.execution.initial.guests.storageFacts = AccumulationStorageFactLimits(
      items: ElementLimit(4), perKey: ByteLimit(8), totalKeyBytes: ByteLimit(32))
  result.completion.execution.execution.round.guests.storageFacts = result.completion.execution.initial.guests.storageFacts
  result.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  result.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
  result.completion.execution.initial.guests.deletedAccounts = ElementLimit(4)
  result.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(4)
proc policy(): LogicalContinuationLimits =
  ## Explicit projection covers up to four whole services; original qualification policies remain independent.
  let logical = namespaceLogicalLimits()
  result = LogicalContinuationLimits(identity: currentIdentityTestLimits, checks: ElementLimit(
      8192), scratchBytes: ByteLimit(262144), projection: namespaceRefreshLimits.projection,
      profile: logical.profile, globals: logical.globals, logical: logical.logical)
  result.projection.services = ElementLimit(4)
proc program(checkpoint = false, panic = false): seq[byte] =
  ## Actual new seeds a one-byte requested code hash, with a real optional checkpoint before the actual selected terminal instruction.
  var payload = newSeq[byte](60)
  payload[32] = 1
  var code = @[registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
      registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20]]
  if checkpoint: code.add(@[10'u8, 19]) # Checkpoint selection retains the complete actual creation effect context.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc replacementProgram(checkpoint = false, panic = false): seq[byte] =
  ## A genuine registrar ejects junior99, optionally checkpoints, then recreates the same reserved ID.
  var payload = newSeq[byte](60)
  payload[32] = 1
  var code = @[registerImmediate(7, 99), @[10'u8, 23]]
  if checkpoint: code.add(@[10'u8, 19]) # This checkpoint precedes creation and retains only ejection.
  code.add(registerImmediate(7, high(uint64)))
  code.add(registerImmediate(8, 99))
  code.add(registerImmediate(9, 0))
  code.add(registerImmediate(10, 196608))
  code.add(@[10'u8, 20])
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc prepare(origin: CurrentNamespaceTransition, members = true): PreparedCurrentChainUpdate {.raises.} =
  ## Collection and joined shutdown release native graph borrowing before any immutable current evidence is inspected.
  var owner = initApplicationChain(origin.update.currentUpdatePriorView).value
  let admitted = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), origin.source.older, candidatePolicy(members))
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  receipt.currentValue.value
proc fixture(eject = false, checkpoint = false, panic = false,
    replace = false): Fixture {.raises.} =
  ## Author complete original namespaces and programs before roots/signatures, including a genuinely empty eligible ejection target.
  var options = executionFixtureConfig()
  options.firstProgram = if replace: replacementProgram(checkpoint, panic)
    elif eject: namespaceEjectCode() else: program(checkpoint, panic)
  options.secondProgram = namespaceHaltCode()
  options.signed.serviceNamespaces = namespaceSeeds()
  if replace: options.registrar = 42 # Authored authority enters the original signed state, never a completed update.
  if eject or replace:
    options.second = ExecutionEnding.Missing
    options.secondSupervisor = 42
    options.signed.serviceNamespaces[1].storage = @[]
    options.signed.serviceNamespaces[1].preimages = @[]
    options.signed.serviceNamespaces[1].requests = @[]
  let origin = namespaceTransitionFixture(nativeBase(), options, ElementLimit(4), candidatePolicy())
  Fixture(origin: origin, update: prepare(origin))
proc check(source: Fixture, count: int): CurrentLogicalState =
  ## Entire actual-map matching and independent raw-key capture are mandatory for every returned logical successor.
  let continued = continueCurrentNamespaces(source.origin.parent, source.update, policy())
  if continued.error != LogicalContinuationError.None:
    echo "service continuation refused: ", continued.error # Preserve the actual failed stage in native diagnostics.
  assert continued.error == LogicalContinuationError.None, $continued.error
  let logical = continued.value
  assert sameStateSnapshot(logical.currentLogicalUpdate.value.currentUpdateState,
      source.update.currentUpdateState)
  let services = copySuppliedServices(logical.currentLogicalInventory.value, policy().projection).value
  assert services.len == count
  logical
proc main() {.raises.} =
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain an explicit absolute fixture binding.
  for checkpoint in [false, true]:
    for panic in [false, true]:
      # Terminal selection uses genuine producer owners: halt retains replacement, panic selects the old or ejected generation.
      let source = fixture(checkpoint = checkpoint, panic = panic, replace = true)
      let count = if panic and checkpoint: 1 else: 2
      let logical = check(source, count)
      let history = source.update.currentUpdateServiceIdentityHistory
      assert history.serviceIdentityHistoryInfo.value.creations == (if panic: 0 else: 1)
      assert history.serviceIdentityHistoryInfo.value.deletions == (if panic and
          not checkpoint: 0 else: 1)
      if not panic:
        let services = copySuppliedServices(logical.currentLogicalInventory.value, policy().projection).value
        var found = false
        for service in services:
          if uint32(service.service) == 99:
            assert service.storage.len == 0 and service.preimages.len == 0 and
                service.requests.len == 1
            assert service.requests[0].history.state == RequestState.Requested
            found = true
        assert found, "the replacement carries its genuine new code request"
        let created = history.serviceIdentityCreationAt(ServiceCreationIndex(0)).value
        let deleted = history.serviceIdentityDeletionAt(ServiceDeletionIndex(0)).value
        assert uint32(created.fact.service) == 99 and uint32(deleted.fact.service) == 99
        assert uint64(created.fact.ordinal) > uint64(deleted.fact.ordinal)
  let grown = fixture()
  let continued = check(grown, 3)
  let created = grown.update.currentUpdateServiceIdentityHistory.serviceIdentityCreationAt(
      ServiceCreationIndex(0)).value.fact
  let services = copySuppliedServices(continued.currentLogicalInventory.value, policy().projection).value
  var found = false
  for service in services:
    # Only a genuine selected new service may add an originally unnamed complete namespace.
    if uint32(service.service) == uint32(created.service):
      assert service.storage.len == 0 and service.preimages.len == 0 and service.requests.len == 1
      assert uint32(service.requests[0].length) == 1 and service.requests[0].history.state ==
          RequestState.Requested
      assert array[32, byte](service.requests[0].hash) == default(array[32, byte])
      found = true
  assert found
  let legacy = continueCurrentStorage(grown.origin.parent, grown.update, policy())
  assert legacy.error == LogicalContinuationError.StateFailure # Complete-map matching refuses the unsupported new service in the storage-only contract.
  let ejected = fixture(eject = true)
  let remaining = check(ejected, 1)
  let remainingServices = copySuppliedServices(remaining.currentLogicalInventory.value, policy().projection).value
  assert uint32(remainingServices[0].service) == 42
  discard check(fixture(panic = true), 2)
  discard check(fixture(checkpoint = true, panic = true), 3)
  let missingCreation = prepare(grown.origin, members = false)
  assert continueCurrentNamespaces(grown.origin.parent, missingCreation, policy()).error ==
      LogicalContinuationError.UnsupportedChange
  let missingDeletion = prepare(ejected.origin, members = false)
  assert continueCurrentNamespaces(ejected.origin.parent, missingDeletion, policy()).error ==
      LogicalContinuationError.UnsupportedChange
  let crossed = continueCurrentNamespaces(ejected.origin.parent, grown.update, policy())
  assert crossed.identityFailure.error == CurrentIdentityError.ParentMismatch
  fail(1)
  for kind in 0..<4:
    # Whole service cardinality, roster scratch, planning and minimum output bytes refuse before request hashing.
    var short = policy()
    case kind
    of 0: short.projection.services = ElementLimit(
        2) # Genuine creation does not evade final service extent admission.
    of 1: short.scratchBytes = ByteLimit(0) # No descriptor array is allocated before complete scratch admission.
    of 2: short.checks = ElementLimit(0) # Even the first original service observation consumes work.
    else: short.projection.bytes = ByteLimit(0) # Fixed output minima precede namespace hash derivation.
    let refused = continueCurrentNamespaces(grown.origin.parent, grown.update, short)
    assert refused.error == LogicalContinuationError.LimitExceeded and calls() == 0
  let backend = continueCurrentNamespaces(grown.origin.parent, grown.update, policy())
  assert backend.requestError == RequestError.BackendFailure
  fail(0)
  var short = policy()
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
  assert copySuppliedServices(repeated.value.currentLogicalInventory.value, policy().projection).value.len == 4
  for i in 0..<25: discard continueCurrentNamespaces(grown.origin.parent, grown.update, policy()).value # Warm complete roster reconstruction/current qualification.
  let before = getOccupiedMem()
  for i in 0..<1000: discard continueCurrentNamespaces(grown.origin.parent, grown.update, policy()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("service_logical_continuation", 1000, before, after)
  echo "service-logical-continuation: ok"
try:
  main()
except:
  quit(2) # Unexpected fixture or qualification refusal cannot count as successful logical continuation.
