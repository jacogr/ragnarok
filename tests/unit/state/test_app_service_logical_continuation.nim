# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc":"service_logical_continuation_arc_release"}

## Real native service creation/ejection continues complete logical state without supplied successor declarations, while missing evidence and unsupported generations remain closed.
import std/assertions
import std/syncio
import std/envvars
import ../../support/app_collected_native_context
import ../../support/app_collected_logical_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_service_replacement_context
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
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../../src/state/logical_continuation as state_logical_continuation
import ../../../src/state/service_identity_history as state_service_identity_history
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
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
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
  options.firstProgram = if replace: namespaceReplacementCode(checkpoint, panic)
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
        let missing = prepare(source.origin, members = false)
        assert continueCurrentNamespaces(source.origin.parent, missing, policy()).error ==
          LogicalContinuationError.UnsupportedChange, "unchanged ID still needs lifecycle evidence for a new incarnation"
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
  var sequentialPolicy = candidatePolicy()
  sequentialPolicy.round.blockGas = Gas(200000)
  let sequential = namespaceSequentialReplacementFixture(nativeBase(), sequentialPolicy)
  let selected = sequential.update.currentUpdateServiceIdentityHistory
  assert selected.serviceIdentityHistoryInfo.value.creations == 1
  assert selected.serviceIdentityHistoryInfo.value.deletions == 1
  let producer = selected.serviceIdentityHistorySource.value
  assert producer.completedSequenceInfo.value.entries == 2
  let creation = selected.serviceIdentityCreationAt(ServiceCreationIndex(0)).value
  let deletion = selected.serviceIdentityDeletionAt(ServiceDeletionIndex(0)).value
  assert uint64(deletion.entry) < uint64(creation.entry)
  let continuedSequence = check(Fixture(origin: sequential, update: sequential.update), 2)
  let declarations = copySuppliedServices(continuedSequence.currentLogicalInventory.value, policy().projection).value
  var selectedReplacement = false
  for service in declarations:
    if uint32(service.service) == 99:
      assert service.requests.len == 1 and service.preimages.len == 0 and service.storage.len == 0
      assert uint32(service.requests[0].length) == 0
      assert service.requests[0].history.state == RequestState.Requested
      selectedReplacement = true
  assert selectedReplacement
  assert continueCurrentStorage(sequential.parent, sequential.update, policy()).error ==
      LogicalContinuationError.UnsupportedChange
  var missingPolicy = sequentialPolicy
  missingPolicy.serviceIdentities = default(ServiceIdentityHistoryLimits)
  let missingSequence = namespaceSequentialReplacementFixture(nativeBase(), missingPolicy)
  let missingContinuation = continueCurrentNamespaces(missingSequence.parent,
    missingSequence.update, policy())
  assert missingContinuation.error == LogicalContinuationError.UnsupportedChange
  var retirementPolicy = candidatePolicy()
  retirementPolicy.completion.execution.initial.guests.accountWriteFacts = ElementLimit(16)
  retirementPolicy.completion.execution.initial.accounts.writes.writes = ElementLimit(16)
  let retired = namespaceRetiredReplacementFixture(nativeBase(), retirementPolicy)
  let retiredHistory = retired.update.currentUpdateServiceIdentityHistory
  assert retiredHistory.serviceIdentityHistoryInfo.value.creations == 1
  assert retiredHistory.serviceIdentityHistoryInfo.value.deletions == 1
  assert retiredHistory.serviceIdentityHistorySource.value.completedSequenceInfo.value.entries == 3
  let death = retiredHistory.serviceIdentityDeletionAt(ServiceDeletionIndex(0)).value
  let birth = retiredHistory.serviceIdentityCreationAt(ServiceCreationIndex(0)).value
  assert uint64(death.entry) == 1 and uint64(birth.entry) == 2
  discard check(Fixture(origin: retired, update: retired.update), 2)
  let reused = namespaceRetiredReplacementFixture(nativeBase(), retirementPolicy, reuse = true)
  discard check(Fixture(origin: reused, update: reused.update), 2)
  let orphan = namespaceRetiredReplacementFixture(nativeBase(), retirementPolicy, orphan = true)
  let rejectedOrphan = continueCurrentNamespaces(orphan.parent, orphan.update, policy())
  assert rejectedOrphan.error == LogicalContinuationError.UnsupportedChange
  var postBirthPolicy = retirementPolicy
  postBirthPolicy.completion.execution.execution.round.guests.provisions = AccumulationProvisionLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  postBirthPolicy.completion.execution.execution.round.provisions.values = PreimageLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  postBirthPolicy.completion.execution.execution.round.provisions.encodedBytes = ByteLimit(128)
  let postBirth = namespaceRetiredReplacementFixture(nativeBase(), postBirthPolicy,
      postBirth = true)
  let postLogical = check(Fixture(origin: postBirth, update: postBirth.update), 2)
  let postServices = copySuppliedServices(postLogical.currentLogicalInventory.value, policy().projection).value
  var postFound = false
  for service in postServices:
    if uint32(service.service) == 99:
      assert service.storage.len == 1 and service.preimages.len == 1 and service.requests.len == 2
      assert service.storage[0].key == @[5'u8] and service.storage[0].value == @[8'u8]
      assert service.preimages[0].value == @[77'u8]
      postFound = true
  assert postFound
  var checkpointPolicy = retirementPolicy
  checkpointPolicy.completion.execution.initial.guests.provisions = AccumulationProvisionLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  checkpointPolicy.completion.execution.initial.provisions.values = PreimageLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  checkpointPolicy.completion.execution.initial.provisions.encodedBytes = ByteLimit(128)
  let checkpoint = namespaceAtomicReplacementFixture(nativeBase(), checkpointPolicy)
  let checkpointHistory = checkpoint.update.currentUpdateServiceIdentityHistory
  assert checkpointHistory.serviceIdentityHistorySource.value.completedSequenceInfo.value.entries == 1
  let barrier = checkpointHistory.serviceIdentityRetirementAt(ServiceCreationIndex(0),
      ServiceDeletionIndex(0))
  assert barrier.error == ServiceIdentityHistoryError.None
  assert barrier.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(99))).error ==
      StateStoreError.MissingKey
  assert checkpointHistory.serviceIdentityRetirementAt(ServiceCreationIndex(high(uint64)),
      ServiceDeletionIndex(0)).error == ServiceIdentityHistoryError.InvalidIndex
  assert default(ServiceIdentityHistory).serviceIdentityRetirementAt(ServiceCreationIndex(0),
      ServiceDeletionIndex(0)).error == ServiceIdentityHistoryError.InvalidSource
  let checkpointLogical = check(Fixture(origin: checkpoint, update: checkpoint.update), 2)
  let checkpointServices = copySuppliedServices(checkpointLogical.currentLogicalInventory.value,
      policy().projection).value
  var checkpointFound = false
  for service in checkpointServices:
    # Coalesced old identities need refreshed phase evidence and genuine absence in the earlier checkpoint.
    if uint32(service.service) == 99:
      assert service.storage.len == 1 and service.preimages.len == 1 and service.requests.len == 2
      assert service.storage[0].key == @[5'u8] and service.storage[0].value == @[8'u8]
      assert service.preimages[0].value == @[77'u8]
      checkpointFound = true
  assert checkpointFound
  for kind in 0..<3:
    # A selected atomic ejection map permits reuse without a guest checkpoint or with a later checkpoint; an orphan still refuses.
    let unsupported = namespaceAtomicReplacementFixture(nativeBase(), checkpointPolicy,
      checkpoint = kind != 0, late = kind == 1, orphan = kind == 2)
    let refusal = continueCurrentNamespaces(unsupported.parent, unsupported.update, policy())
    if kind == 2:
      assert refusal.error == LogicalContinuationError.UnsupportedChange # Metadata removal cannot erase the orphan identity.
    else:
      assert refusal.error == LogicalContinuationError.None # Genuine ejection is the barrier independently of guest checkpoint placement.
  let checkpointPanic = namespaceAtomicReplacementFixture(nativeBase(), checkpointPolicy, panic = true)
  discard check(Fixture(origin: checkpointPanic, update: checkpointPanic.update), 1)
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
  for i in 0..<1000:
    # Both ordinary additions and retired-generation aliases must release every temporary owner.
    discard continueCurrentNamespaces(grown.origin.parent, grown.update, policy()).value
    discard continueCurrentNamespaces(retired.parent, retired.update, policy()).value
    discard continueCurrentNamespaces(reused.parent, reused.update, policy()).value
    discard continueCurrentNamespaces(postBirth.parent, postBirth.update, policy()).value
    discard continueCurrentNamespaces(checkpoint.parent, checkpoint.update, policy()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_service_logical_continuation", 1000, before, after)
  echo "service-logical-continuation: ok"
try:
  main()
except:
  quit(2) # Unexpected fixture or qualification refusal cannot count as successful logical continuation.
