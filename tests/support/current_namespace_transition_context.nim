# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine complete signed custom-code namespace transitions and explicit original declarations; no private current owner is fabricated.
import std/assertions
import ./[current_namespace_context, service_namespace_seed, current_namespace_execution_context,
    accumulation_activity_context, accumulation_execution_context,
    accumulation_current_candidate_context, parent_profile_context, parent_globals_context,
    supplied_logical_context, pvm_accumulation_program]
import ../../src/codec/[bounded, report_owned, state_accounts, state_composition, state_requests, state_service_values]
import ../../src/crypto/primitives
import ../../src/state/[parent_profile, parent_globals, parent_logical, store,
    accumulation_current_update, accumulation_round, accumulation_queue, report_admission,
    block_transition, block_admission]
import ../../src/app/[chain, candidate]
type CurrentNamespaceTransition* = object ## Test descriptors retain actual source inputs, complete original logical selection and genuine current update independently.
  source*: ExecutionFixture
  parent*: SelectedLogicalParent
  update*: PreparedCurrentChainUpdate
  services*: seq[StateService]
proc namespaceStorageCode*(value: seq[byte]): seq[byte] =
  ## Maintained host-write convention targets current service raw key7; zero length invokes actual deletion rather than storing present-empty.
  assert value.len <= 65
  var writable = @[7'u8]
  for octet in value: writable.add(octet) # Exact authored bytes follow the one-byte raw key in initialized guest memory.
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, uint64(
      value.len)), @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(
      octet) # Whole original code preimage uses existing execution framing.
proc namespaceEjectCode*(): seq[byte] =
  ## Existing eject host authenticates the invoker's empty junior99; ordinary halt follows the charged response.
  result = @[0'u8]
  for octet in guestEnvelope([registerImmediate(7, 99), @[10'u8, 23], @[50'u8, 0]]): result.add(octet)
proc namespaceTransitionFixture*(base: OwnedReport, options: ExecutionFixtureConfig,
    deleted = ElementLimit(0)): CurrentNamespaceTransition =
  ## Complete original namespaces/code requests enter roots and signatures before actual candidate execution under explicit deletion policy.
  var config = options
  assert config.signed.extra.len == 0 and config.signed.serviceNamespaces.len == 2
  let codes = [config.firstProgram, config.secondProgram]
  let endings = [config.first, config.second]
  var seeds = config.signed.serviceNamespaces
  for i in 0..<2:
    assert codes[i].len > 0 and codes[i].len <= 65536
    if endings[i] != ExecutionEnding.Missing:
      let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[i]).value))
      seeds[i].requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(codes[
          i].len)), history: availableHistory(RequestSlot(
          1)))) # Code already added by ExecutionFixture is declared, never duplicated.
  config.signed.serviceNamespaces = seeds
  config.signed.completeState = true
  config.signed.extra = @[activityParentEntry()]
  let source = executionFixture(base, config)
  let view = source.executionNamespaceParent
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let snapshot = profile.parentContext.value.state
  var services = currentNamespaceServices(snapshot, seeds)
  for i in 0..<2:
    if endings[i] != ExecutionEnding.Missing:
      let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[i]).value))
      let key = servicePreimageKey(services[i].service, hash, ByteLimit(32)).value
      let raw = snapshot.lookup(key).value.bytes
      assert raw == codes[i]
      services[i].preimages.add(StatePreimageItem(hash: hash,
          value: raw)) # Complete original declarations include exactly the actually added code preimage.
  let parent = captureLogicalParent(globals, services, suppliedLogicalTestLimits).value
  let admission = source.round.roundBlockQueue.value.accumulationAdmission.value
  let bound = admission.reportBlockStage.value.value.admitted
  var limits = currentCandidateLimits()
  limits.completion.execution.initial.guests.deletedAccounts = deleted
  limits.completion.execution.execution.round.guests.deletedAccounts = deleted
  let application = initApplicationChain(view).value
  let update = prepareCurrentCandidate(application, bound.admittedBlock, source.older, limits).value
  CurrentNamespaceTransition(source: source, parent: parent, update: update, services: services)
