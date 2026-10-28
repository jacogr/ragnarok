# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine custom-code signed complete parents expose explicit auto-added code declarations without duplicate metadata/preimages.
import std/assertions
import ./state_current_namespace_context
import ./codec_service_namespace_seed
import ./state_accumulation_activity_context
import ./state_accumulation_execution_context
import ./state_accumulation_current_chain_context
import ./state_accumulation_current_candidate_context
import ./pvm_accumulation_program
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/report_owned as codec_report_owned
import ../../src/crypto/primitives as crypto_primitives
import ../../src/state/store as state_store
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
type NamespaceExecutionFixture* = object ## Explicit authored namespaces/code belong to the same real admitted original parent and current update.
  source*: ExecutionFixture
  seeds*: seq[ServiceNamespaceSeed]
  codes*: array[2, seq[byte]]
  parent*: ChainView
  update*: PreparedCurrentChainUpdate
proc namespaceHaltCode*(): seq[byte] =
  ## Existing whole-code framing prefixes maintained guestEnvelope with the single code metadata octet.
  result = @[0'u8]
  for octet in guestEnvelope([@[50'u8, 0]]): result.add(octet)
proc executionNamespaceParent*(source: ExecutionFixture, parameters = currentChainSettings()): ChainView =
  ## Capture exact original signed parent/state/Parameters without inventing completion authority.
  let admission = source.round.roundBlockQueue.value.accumulationAdmission.value
  let bound = admission.reportBlockStage.value.value.admitted
  let captured = captureBlockSnapshot(currentChainBytes(bound.admittedParent),
      source.state.snapshot.value, parameters)
  assert captured.error == GenesisError.None
  genesisView(captured).finalizeView(captured.value.blockHash).value
proc prepareNamespaceExecution*(source: ExecutionFixture, policies = currentCandidateLimits()): PreparedCurrentChainUpdate =
  ## Run actual current candidate preparation on the execution fixture's exact original state/full view.
  let admission = source.round.roundBlockQueue.value.accumulationAdmission.value
  let bound = admission.reportBlockStage.value.value.admitted
  let app = initApplicationChain(source.executionNamespaceParent).value
  prepareCurrentCandidate(app, bound.admittedBlock, source.older, policies).value
proc namespaceExecutionFixture*(base: OwnedReport, first, second: seq[byte],
    secondBalance = 1000000'u64, policies = currentCandidateLimits()): NamespaceExecutionFixture =
  ## Code preimages are added by the maintained execution fixture; only their explicit request rows join our namespace seed.
  var seeds = namespaceSeeds()
  let codes = [first, second]
  for i in 0..<2:
    assert codes[i].len <= 65536 # Explicit whole-code extent stays inside supplied-map per-value policy.
    let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[i]).value))
    seeds[i].requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(codes[i].len)),
        history: availableHistory(RequestSlot(1))))
  var options = executionFixtureConfig()
  options.first = ExecutionEnding.Halt
  options.second = ExecutionEnding.Halt
  options.firstProgram = first
  options.secondProgram = second
  options.secondBalance = secondBalance
  options.signed.completeState = true
  options.signed.serviceNamespaces = seeds
  options.signed.extra = @[activityParentEntry()]
  let source = executionFixture(base, options)
  let parent = source.executionNamespaceParent
  let update = source.prepareNamespaceExecution(policies)
  NamespaceExecutionFixture(source: source, seeds: seeds, codes: codes, parent: parent,
      update: update)
proc executableNamespaceServices*(fixture: NamespaceExecutionFixture,
    snapshot: StateStoreSnapshot): seq[StateService] =
  ## Complete supplied declarations explicitly add each actual code preimage already committed by ExecutionFixture.
  result = currentNamespaceServices(snapshot, fixture.seeds)
  let limits = ByteLimit(32)
  for i in 0..<2:
    if fixture.codes[i].len > 0:
      # Only executable slots add code preimages; prequalified complete declarations leave slots empty.
      let hash = ServicePreimageHash(array[32, byte](blake2b256(fixture.codes[i]).value))
      let key = servicePreimageKey(result[i].service, hash, limits).value
      let raw = snapshot.lookup(key).value.bytes
      assert raw == fixture.codes[i]
      result[i].preimages.add(StatePreimageItem(hash: hash, value: raw))
