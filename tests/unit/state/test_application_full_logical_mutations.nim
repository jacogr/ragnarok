# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete proof transport preserves real selected namespace mutations and rollback, while missing individual witnesses become absence only after checked whole-map reconstruction.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
  current_namespace_context,
  current_namespace_transition_context, current_namespace_execution_context,
  accumulation_execution_context,
  current_identity_context, pvm_accumulation_program, service_namespace_seed,
  current_logical_proof_context, supplied_services_context, current_namespace_refresh_context]
import ../../../src/app/[full_logical_proof, logical_proof, proof_query, collected_supplied_state,
  preparation_worker, current_block_input, logical_code]
import ../../../src/state/[current_identities, current_logical, current_state, current_globals,
  current_profile, supplied_logical_inventory, supplied_services, accumulation_current_update,
  store, planned_proof, proof_plan, proof_view, proof_state_import, trie_proof,
  global_snapshot, manifest, code_availability]
import ../../../src/codec/[bounded, state_layout, state_accounts, state_composition,
  state_service_values, state_requests, state_trie]
import ../../../src/crypto/primitives
import ../../../src/chain/genesis
proc checkTransport(fixture: CollectedMutationFixture, present: bool, payload: seq[byte]) =
  ## Actual selected source, not an operation trace or equal-root substitute, determines the complete exported keys and independently selected expected commitment.
  let logical = qualifyMutation(fixture)
  let source = logical.currentLogicalContext.value.state
  let root = source.commitment.root
  let plan = planFullLogicalProof(logical, FullLogicalProofLimits(keys: ElementLimit(128),
      bytes: ByteLimit(16384))).value
  let keys = plan.fullLogicalProofKeys.value
  var limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  limits.query.aggregate.items = ElementLimit(128)
  limits.query.aggregate.nodes = ElementLimit(31872)
  limits.query.view.items = ElementLimit(128)
  let response = executeProofQuery(captureFullLogicalProofQuery(plan, limits).value).value
  let wire = response.bytes(limits.query.wireBytes).value
  let view = decodePlannedProofs(wire, keys, root, limits.query.view, limits.query.proof,
      limits.query.aggregate, limits.query.wireBytes).value
  let restored = importProofState(view, root, ProofStateImportLimits(lookups: ElementLimit(128),
      copyBytes: ByteLimit(1048576), store: genesisStoreLimits())).value.snapshot.value
  assert not sameStateSnapshot(restored, source) and restored.commitment.entries ==
      source.commitment.entries
  for i in 0..<source.commitment.entries:
    let key = source.keyAt(store.StateEntryIndex(i)).value
    assert restored.lookup(key).value.bytes == source.lookup(
        key).value.bytes # Every original global, metadata and namespace byte survives, including unmodified siblings.
  if present:
    assert source.lookup(fixture.key).value.bytes == payload
    assert view.lookup(fixture.key).value.present and view.lookup(fixture.key).value.bytes == payload
    assert restored.lookup(fixture.key).value.bytes == payload
  else:
    assert source.lookup(fixture.key).error == StateStoreError.MissingKey
    assert view.lookup(fixture.key).error == ProofViewError.MissingWitness # Full-present-key selection does not request a deleted key's individual absence witness.
    assert restored.lookup(fixture.key).error == StateStoreError.MissingKey # Only independently matched full-map commitment now authorizes complete absence.
  let declarations = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  let policy = namespaceLogicalLimits()
  let profile = logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedStateProfile.value
  let globals = validateGlobalState(restored, profile, policy.globals).value
  let complete = validateStateManifest(globals, declarations,
      policy.logical.inventory.manifest).value
  let qualified = captureSuppliedLogicalInventory(complete, declarations, policy.logical).value
  let codeLimits = CodeAvailabilityLimits(services: ElementLimit(2), visits: ElementLimit(128),
      descriptors: ByteLimit(65536), perCode: ByteLimit(65536), totalCodeBytes: ByteLimit(131072))
  let originalCodes = auditLogicalCodeAvailability(logical, codeLimits).value.logicalCodeTable
  let importedCodes = auditCodeAvailability(qualified.suppliedInventory.value, RequestSlot(
      logical.currentLogicalContext.value.slot), codeLimits).value
  assert importedCodes.codeAvailabilityInfo.value.services ==
      originalCodes.codeAvailabilityInfo.value.services
  for i in 0..<originalCodes.codeAvailabilityInfo.value.services:
    let original = originalCodes.serviceCodeAt(i).value
    let copied = importedCodes.findServiceCode(original.service).value
    assert importedCodes.serviceCodeAt(copied).value.state == original.state
    if original.state == ServiceCodeState.Available:
      assert importedCodes.copyServiceCode(copied, ByteLimit(65536)).value ==
          originalCodes.copyServiceCode(i, ByteLimit(65536)).value

proc storageAddition() {.raises.} =
  ## Service99 is funded before signatures; its real host write creates raw key7 while every untouched raw identity remains explicitly supplied.
  let value = @[91'u8, 92, 93]
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(value)
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  assert fixture.receipt.currentValue.value.currentUpdatePriorState.lookup(key).error ==
      StateStoreError.MissingKey
  let refusal = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refusal.error == CurrentIdentityError.NewIdentity
  checkTransport(fixture, true, value)

proc storageDeletion() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.secondProgram = namespaceStorageCode(@[])
  options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.setLen(1)
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  assert fixture.receipt.currentValue.value.currentUpdatePriorState.lookup(key).value.bytes == @[
      13'u8, 14, 15]
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.MissingIdentity
  checkTransport(fixture, false, @[])

proc preimageProvision() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.secondProgram = namespaceHaltCode()
  let value = @[88'u8, 89, 90]
  let hash = ServicePreimageHash(array[32, byte](blake2b256(value).value))
  options.signed.serviceNamespaces[1].requests.add(StateRequestItem(hash: hash,
      length: RequestLength(3), history: requestedHistory()))
  options.signed.preimageWire = @[1'u8, 99, 0, 0, 0, 3, 88, 89, 90]
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].preimages.add(StatePreimageItem(hash: hash, value: value))
  expected[1].requests[2].history = availableHistory(RequestSlot(2))
  let key = servicePreimageKey(ServiceIndex(99), hash, ByteLimit(32)).value
  let fixture = collectMutation(origin, expected, key)
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.NewIdentity
  checkTransport(fixture, true, value)

proc requestAddition() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let hash = ServicePreimageHash(array[32, byte](blake2b256([71'u8, 72]).value))
  options.secondProgram = requestMutationCode(hash, RequestLength(2), [25'u8])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests.add(StateRequestItem(hash: hash, length: RequestLength(2),
      history: requestedHistory()))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(2), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.NewIdentity
  checkTransport(fixture, true, @[0'u8])

proc requestRestoration() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let hash = options.signed.serviceNamespaces[1].preimages[1].hash
  options.secondProgram = requestMutationCode(hash, RequestLength(1), [26'u8, 25])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests[1].history = reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(2))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  checkTransport(fixture, true, @[3'u8, 1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0])

proc checkpointSelection() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let value = @[91'u8, 92, 93]
  options.secondProgram = writeMutationCode(value, [@[10'u8, 19], @[0'u8]])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  checkTransport(fixture, true, value)

proc panicRollback() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let value = @[91'u8, 92, 93]
  options.secondProgram = writeMutationCode(value, [@[0'u8]])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  checkTransport(fixture, false, @[])

proc outofgasRollback() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let value = @[91'u8, 92, 93]
  options.secondProgram = writeMutationCode(value, [registerImmediate(11, 65536), @[10'u8, 5], @[
      50'u8, 0]])
  options.allowanceGas = 3000 # Fund the first write; the later 65536-byte host charge is unaffordable before memory access.
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  checkTransport(fixture, false, @[])

proc serviceEjection() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceEjectCode()
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.secondBalance = 0
  options.secondSupervisor = 42
  let initial = namespaceSeeds()
  options.signed.serviceNamespaces = @[initial[0], ServiceNamespaceSeed(service: ServiceIndex(99),
      storage: @[], preimages: @[], requests: @[])]
  let origin = namespaceTransitionFixture(nativeBase(), options, ElementLimit(1))
  var expected = origin.services
  expected.setLen(1)
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  let fixture = collectMutation(origin, expected, key, ElementLimit(1))
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.MissingIdentity
  checkTransport(fixture, false, @[])

proc main() {.raises.} =
  ## One coherent corpus covers all selected namespace and exceptional outcomes, keeping each complete source lifetime isolated.
  storageAddition()
  storageDeletion()
  preimageProvision()
  requestAddition()
  requestRestoration()
  checkpointSelection()
  panicRollback()
  outofgasRollback()
  serviceEjection()
  echo "application-full-logical-mutations: ok"
try:
  main()
except:
  quit(2) # Source construction and actual execution failures cannot become successful transport witnesses.
