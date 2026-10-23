# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine reserved-ID replacement fixtures share signed original namespaces across state and application qualification.
import std/assertions
import ./[current_namespace_transition_context, current_namespace_execution_context,
  accumulation_execution_context, accumulation_current_candidate_context,
  current_namespace_context, service_namespace_seed, pvm_accumulation_program]
import ../../src/codec/[bounded, report_owned, composite, state_accounts, state_composition,
    state_requests, state_service_values]
import ../../src/crypto/primitives
import ../../src/app/candidate
import ../../src/chain/parameters
import ./accumulation_current_chain_context
import ../../src/state/accumulation_current_update
proc namespaceReplacementCode*(checkpoint = false, panic = false): seq[byte] =
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
proc toNamespaceExecutionFixture*(origin: CurrentNamespaceTransition): NamespaceExecutionFixture =
  ## Retain complete original declarations for real command fixtures without adding their existing code preimages twice.
  var seeds: seq[ServiceNamespaceSeed] = @[]
  for service in origin.services:
    # Complete source declarations already contain executable code; empty code slots avoid duplicating those preimages.
    seeds.add(ServiceNamespaceSeed(service: service.service, storage: service.storage,
      preimages: service.preimages, requests: service.requests))
  NamespaceExecutionFixture(source: origin.source, seeds: seeds,
    codes: [newSeq[byte](0), newSeq[byte](0)], parent: origin.update.currentUpdatePriorView,
    update: origin.update)
proc namespaceReplacementFixture*(base: OwnedReport): NamespaceExecutionFixture =
  ## Author an empty junior and real registrar before signing; declarations come from the already-qualified original parent.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceReplacementCode()
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.registrar = 42
  options.secondSupervisor = 42
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage = @[]
  options.signed.serviceNamespaces[1].preimages = @[]
  options.signed.serviceNamespaces[1].requests = @[]
  let origin = namespaceTransitionFixture(base, options, ElementLimit(4), currentCandidateLimits())
  origin.toNamespaceExecutionFixture
proc namespaceSequentialReplacementFixture*(base: OwnedReport,
    policy: CurrentCandidateLimits): CurrentNamespaceTransition =
  ## The first invocation ejects and upgrades itself; the originally queued report later invokes its new creator code.
  let newInstructions = @[@[51'u8, 7, 255], @[51'u8, 8, 99], @[51'u8, 9, 0],
    @[51'u8, 10, 0, 0, 3], @[10'u8, 20], @[50'u8, 0]]
  var nextCode = @[0'u8]
  for octet in guestEnvelope(newInstructions, writable = @[0'u8]): nextCode.add(octet)
  assert nextCode.len <= 65 # The explicit original seed stays within the maintained independent fixture policy.
  let hash = ServicePreimageHash(array[32, byte](blake2b256(nextCode).value))
  var payload: seq[byte] = @[]
  for octet in array[32, byte](hash): payload.add(octet)
  let firstInstructions = @[registerImmediate(7, 99), @[10'u8, 23],
    registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 0), registerImmediate(10, 0), @[10'u8, 21], @[50'u8, 0]]
  var firstCode = @[0'u8]
  for octet in guestEnvelope(firstInstructions, writable = payload): firstCode.add(octet)
  var options = executionFixtureConfig()
  options.firstProgram = firstCode
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.signed.withAvailable = true
  options.signed.accumulationGas = 10000 # A real later new call needs an independently authored report budget.
  options.registrar = 42
  options.secondSupervisor = 42
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage = @[]
  options.signed.serviceNamespaces[1].preimages = @[]
  options.signed.serviceNamespaces[1].requests = @[]
  options.signed.serviceNamespaces[0].preimages.add(StatePreimageItem(hash: hash, value: nextCode))
  options.signed.serviceNamespaces[0].requests.add(StateRequestItem(hash: hash,
    length: RequestLength(uint32(nextCode.len)), history: availableHistory(RequestSlot(1))))
  namespaceTransitionFixture(base, options, ElementLimit(4), policy)
proc retirementImmediate(index: byte, value: uint64): seq[byte] =
  ## Fixed four-byte signed immediates keep multi-host fixtures bounded without self-referential code-length encodings.
  assert value <= 0x7fffffff'u64 or value == high(uint64)
  result = @[51'u8, index]
  for i in 0..<4: result.add(byte((value shr (8*i)) and 255)) # Sign-extension represents the exact self sentinel.
proc retiringCode(length: uint64, hashes: array[2, ServicePreimageHash]): seq[byte] =
  ## Info supplies the executing code hash; expired forget removes that code while its machine retains the original program owner.
  var payload = newSeq[byte](128)
  payload[32] = 5
  for h in 0..<2:
    for i, octet in array[32, byte](hashes[h]): payload[64+h*32+i] = octet
  var code = @[retirementImmediate(7, high(uint64)), retirementImmediate(8, 196608),
    retirementImmediate(9, 0), retirementImmediate(10, 32), @[10'u8, 6],
    retirementImmediate(7, high(uint64)), retirementImmediate(8, 196608),
    retirementImmediate(9, length), @[10'u8, 26]]
  for keyBytes in [0'u64, 1]:
    # Both actual original storage identities are deleted, including the empty raw key.
    for instruction in [retirementImmediate(7, high(uint64)), retirementImmediate(8, 196640),
      retirementImmediate(9, keyBytes), retirementImmediate(10, 196608),
      retirementImmediate(11, 0), @[10'u8, 5]]: code.add(instruction)
  for h in 0..<2:
    # Authored unavailable histories have expired before this signed invocation begins.
    for instruction in [retirementImmediate(7, high(uint64)),
      retirementImmediate(8, uint64(196672+h*32)),
      retirementImmediate(9, uint64(h)), @[10'u8, 26]]: code.add(instruction)
  code.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc retirementDriver(next: seq[byte], eject: bool, forward: uint64): seq[byte] =
  ## Upgrade and genuine self-transfer schedule the next entry after the currently selected namespace work.
  let hash = array[32, byte](blake2b256(next).value)
  var payload: seq[byte] = @[]
  for octet in hash: payload.add(octet)
  var code: seq[seq[byte]] = @[]
  if eject:
    code.add(retirementImmediate(7, 99))
    code.add(@[10'u8, 23]) # Only the later entry sees the junior emptied by its own initial invocation.
  for instruction in [retirementImmediate(7, high(uint64)), retirementImmediate(8, 196608),
    retirementImmediate(9, 0), retirementImmediate(10, 0), @[10'u8, 21],
    retirementImmediate(7, high(uint64)), retirementImmediate(8, 42),
    retirementImmediate(9, 0), retirementImmediate(10, 0), retirementImmediate(11, forward),
    retirementImmediate(12, 196640), @[10'u8, 22], @[50'u8, 0]]: code.add(instruction)
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc namespaceRetiredReplacementFixture*(base: OwnedReport,
    policy: CurrentCandidateLimits, reuse = false, orphan = false): CurrentNamespaceTransition =
  ## All code, histories, budgets and Parameters precede source roots/signatures; selected producer history is never rewritten.
  var seeds = namespaceSeeds()
  let hashes = [seeds[1].preimages[0].hash, seeds[1].preimages[1].hash]
  let sizing = retiringCode(0, hashes)
  let cleanup = retiringCode(uint64(sizing.len), hashes)
  assert cleanup.len == sizing.len # Fixed-width immediates make the independently authored self-length exact.
  var payload = newSeq[byte](60)
  if reuse:
    # Recreate the exact original code request after its proven absence, rather than choosing a new unrelated hash.
    let hash = array[32, byte](blake2b256(cleanup).value)
    for i, octet in hash: payload[i] = octet
    for i in 0..<4: payload[32+i] = byte((uint32(cleanup.len) shr (8*i)) and 255)
  var creator = @[0'u8]
  let instructions = @[retirementImmediate(7, high(uint64)), retirementImmediate(8, 99),
    retirementImmediate(9, 0), retirementImmediate(10, 196608), @[10'u8, 20], @[50'u8, 0]]
  for octet in guestEnvelope(instructions, writable = payload): creator.add(octet)
  let bridge = retirementDriver(creator, true, 10000)
  let first = retirementDriver(bridge, false, 50000)
  for code in [bridge, creator]:
    # Both future programs are present and requested in the original complete namespace before self-upgrade.
    let hash = ServicePreimageHash(array[32, byte](blake2b256(code).value))
    seeds[0].preimages.add(StatePreimageItem(hash: hash, value: code))
    seeds[0].requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(code.len)),
      history: availableHistory(RequestSlot(1))))
  for i in 0..<seeds[1].requests.len:
    # Only originally unavailable, sufficiently old histories authorize destructive forget.
    seeds[1].requests[i].history = unavailableHistory(RequestSlot(0), RequestSlot(1))
  if orphan:
    let hash = ServicePreimageHash(array[32, byte](blake2b256([3'u8]).value))
    seeds[1].preimages.add(StatePreimageItem(hash: hash, value: @[
        3'u8])) # Negative complete-map source must not legitimize an orphan across generations.
  var options = executionFixtureConfig()
  options.firstProgram = first
  options.secondProgram = cleanup
  options.registrar = 42
  options.secondSupervisor = 42
  options.signed.targetSlot = 5000
  options.signed.namespaceValueBytes = 512
  options.signed.serviceNamespaces = seeds
  var wire = encodeParameters(currentChainSettings())
  for i in 74..<78: wire[i] = 0 # Original zero anchor age makes strict4800-slot expiry true at the signed slot5000.
  let parameters = decodeParameters(wire).value
  namespaceTransitionFixture(base, options, ElementLimit(4), policy, parameters,
    unavailableHistory(RequestSlot(0), RequestSlot(1)))
