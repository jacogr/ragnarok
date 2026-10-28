# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine complete signed custom-code namespace transitions and explicit original declarations; no private current owner is fabricated.
import std/assertions
import std/syncio
import ./state_current_namespace_context
import ./codec_service_namespace_seed
import ./state_current_namespace_execution_context
import ./state_accumulation_activity_context
import ./state_accumulation_execution_context
import ./state_accumulation_current_candidate_context
import ./state_accumulation_current_chain_context
import ./state_parent_profile_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ./pvm_accumulation_program
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/crypto/primitives as crypto_primitives
import ../../src/state/parent_profile as state_parent_profile
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/store as state_store
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_current_completion as state_accumulation_current_completion
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
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
    deleted = ElementLimit(0), policy = currentCandidateLimits(),
    parameters = currentChainSettings(),
    secondCodeHistory = availableHistory(RequestSlot(1))): CurrentNamespaceTransition =
  ## Complete original namespaces/code requests enter roots and signatures before actual execution under explicit deletion and composition policies.
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
          i].len)), history: (if i == 1: secondCodeHistory else: availableHistory(RequestSlot(
              1))))) # Code already added by ExecutionFixture is declared, never duplicated.
  config.signed.serviceNamespaces = seeds
  config.signed.completeState = true
  config.signed.extra = @[activityParentEntry()]
  let source = executionFixture(base, config)
  let view = source.executionNamespaceParent(parameters)
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
  var limits = policy
  limits.completion.execution.initial.guests.deletedAccounts = deleted
  limits.completion.execution.execution.round.guests.deletedAccounts = deleted
  let application = initApplicationChain(view).value
  let prepared = prepareCurrentCandidate(application, bound.admittedBlock, source.older, limits)
  if prepared.error != CurrentCandidateError.None:
    # Preserve the genuine failed stage without extracting any refused candidate.
    echo "namespace preparation refused ", prepared.error
    if prepared.error == CurrentCandidateError.CompletionFailure:
      # Nested completion diagnostics apply only to that selected refusal.
      echo "completion refused ", prepared.completionFailure.error
  let update = prepared.value
  CurrentNamespaceTransition(source: source, parent: parent, update: update, services: services)
