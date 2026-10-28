# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine reserved-ID replacement fixtures share signed original namespaces across state and application qualification.
import std/assertions
import ./state_current_namespace_transition_context
import ./state_current_namespace_execution_context
import ./state_accumulation_execution_context
import ./state_accumulation_current_candidate_context
import ./state_current_namespace_context
import ./codec_service_namespace_seed
import ./pvm_accumulation_program
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/crypto/primitives as crypto_primitives
import ../../src/app/candidate as app_candidate
import ../../src/chain/parameters as chain_parameters
import ./state_accumulation_current_chain_context
import ../../src/state/accumulation_current_update as state_accumulation_current_update
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
    policy: CurrentCandidateLimits, reuse = false, orphan = false,
    postBirth = false): CurrentNamespaceTransition =
  ## All code, histories, budgets and Parameters precede source roots/signatures; selected producer history is never rewritten.
  var seeds = namespaceSeeds()
  let hashes = [seeds[1].preimages[0].hash, seeds[1].preimages[1].hash]
  let sizing = retiringCode(0, hashes)
  let cleanup = retiringCode(uint64(sizing.len), hashes)
  assert cleanup.len == sizing.len # Fixed-width immediates make the independently authored self-length exact.
  var payload = newSeq[byte](if postBirth: 128 else: 60)
  if reuse:
    # Recreate the exact original code request after its proven absence, rather than choosing a new unrelated hash.
    let hash = array[32, byte](blake2b256(cleanup).value)
    for i, octet in hash: payload[i] = octet
    for i in 0..<4: payload[32+i] = byte((uint32(cleanup.len) shr (8*i)) and 255)
  var creator = @[0'u8]
  var instructions = @[retirementImmediate(7, high(uint64)), retirementImmediate(8, 99),
    retirementImmediate(9, 0), retirementImmediate(10, 196608), @[10'u8, 20]]
  if postBirth:
    # The new supervisor writes, solicits and provides original identities only AFTER the successful creation call.
    payload[60] = 5
    payload[61] = 8
    payload[62] = 77
    for i, octet in array[32, byte](hashes[1]): payload[64+i] = octet
    for instruction in [retirementImmediate(7, 99), retirementImmediate(8, 196668),
      retirementImmediate(9, 1), retirementImmediate(10, 196669), retirementImmediate(11, 1), @[
          10'u8, 5],
      retirementImmediate(7, 99), retirementImmediate(8, 196672), retirementImmediate(9, 1), @[
          10'u8, 25],
      retirementImmediate(7, 99), retirementImmediate(8, 196670), retirementImmediate(9, 1), @[
          10'u8, 28]]:
      instructions.add(instruction) # Every host result overwrites r7, so each next target is restored explicitly.
  instructions.add(@[50'u8, 0])
  for octet in guestEnvelope(instructions, writable = payload): creator.add(octet)
  let bridge = retirementDriver(creator, true, if postBirth: 20000'u64 else: 10000'u64)
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

proc checkpointImmediate(index: byte, value: uint64): seq[byte] =
  ## Compact signed small constants keep the real cleanup/replacement program within the shared guest envelope.
  if value <= 127 or value == high(uint64):
    return @[51'u8, index, byte(value and 255)] # One-byte sign extension represents the self sentinel exactly.
  retirementImmediate(index, value)
proc namespaceAtomicReplacementFixture*(base: OwnedReport,
    policy: CurrentCandidateLimits, checkpoint = true, late = false,
    orphan = false, panic = false): CurrentNamespaceTransition =
  ## One actual supervisor empties, ejects, checkpoints and recreates its nonexecuting junior before new-generation writes.
  var seeds = namespaceSeeds()
  var payload = newSeq[byte](192)
  let halt = namespaceHaltCode()
  let haltHash = ServicePreimageHash(array[32, byte](blake2b256(halt).value))
  seeds[0].preimages.add(StatePreimageItem(hash: haltHash, value: halt))
  seeds[0].requests.add(StateRequestItem(hash: haltHash,
    length: RequestLength(uint32(halt.len)), history: availableHistory(RequestSlot(1))))
  for i, octet in array[32, byte](haltHash): payload[
      160+i] = octet # Original idle code lets later empty children verify durable state without repeating cleanup.
  for h in 0..<2:
    # Full original hashes precede signatures and identify the only old requests removed by the guest.
    for i, octet in array[32, byte](seeds[1].preimages[h].hash): payload[h*32+i] = octet
    seeds[1].requests[h].history = unavailableHistory(RequestSlot(0), RequestSlot(1))
  payload[64] = 5
  payload[65] = 8
  payload[66] = 77
  var instructions: seq[seq[byte]] = @[]
  for length in [0'u64, 1]:
    # Both old raw keys are removed; zero value length invokes deletion without reading value bytes.
    for instruction in [checkpointImmediate(7, 99), checkpointImmediate(8, 196672),
      checkpointImmediate(9, length), checkpointImmediate(10, 0),
      checkpointImmediate(11, 0), @[10'u8, 5]]: instructions.add(instruction)
  for h in 0..<2:
    # Original unavailable histories have expired under the original slot/Parameters, so forget also removes the old blobs.
    for instruction in [checkpointImmediate(7, 99), checkpointImmediate(8, uint64(196608+h*32)),
      checkpointImmediate(9, uint64(h)), @[10'u8, 26]]: instructions.add(instruction)
  instructions.add(checkpointImmediate(7, 99))
  instructions.add(@[10'u8, 23])
  if checkpoint and not late:
    instructions.add(@[10'u8, 19]) # Only this interval proves the old namespace retired before the new birth.
  for instruction in [checkpointImmediate(7, high(uint64)), checkpointImmediate(8, 99),
    checkpointImmediate(9, 0), checkpointImmediate(10, 196704), @[10'u8, 20],
    checkpointImmediate(7, 99), checkpointImmediate(8, 196672), checkpointImmediate(9, 1),
    checkpointImmediate(10, 196673), checkpointImmediate(11, 1), @[10'u8, 5],
    checkpointImmediate(7, 99), checkpointImmediate(8, 196640), checkpointImmediate(9, 1), @[10'u8, 25],
    checkpointImmediate(7, 99), checkpointImmediate(8, 196674), checkpointImmediate(9, 1), @[10'u8, 28]]:
    instructions.add(instruction) # Each host result replaces r7; every next foreign target is restored explicitly.
  for instruction in [checkpointImmediate(7, high(uint64)), checkpointImmediate(8, 196768),
    checkpointImmediate(9, 0), checkpointImmediate(10, 0), @[10'u8, 21]]:
    instructions.add(instruction) # A genuine final self-upgrade leaves subsequent blocks on independently supplied idle code.
  if checkpoint and late:
    instructions.add(@[10'u8, 19]) # A post-birth checkpoint is genuine but cannot certify the required earlier barrier.
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  var program = @[0'u8]
  for octet in guestEnvelope(instructions, writable = payload): program.add(octet)
  if orphan:
    let hash = ServicePreimageHash(array[32, byte](blake2b256([3'u8]).value))
    seeds[1].preimages.add(StatePreimageItem(hash: hash, value: @[
        3'u8])) # Metadata disappearance cannot certify an untouched orphan absent.
  var options = executionFixtureConfig()
  options.firstProgram = program
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.registrar = 42
  options.secondSupervisor = 42
  options.signed.targetSlot = 5000
  options.signed.namespaceValueBytes = 512
  options.signed.serviceNamespaces = seeds
  var wire = encodeParameters(currentChainSettings())
  for i in 74..<78: wire[i] = 0 # Authored zero anchor age admits strict expiry at slot5000.
  namespaceTransitionFixture(base, options, ElementLimit(4), policy, decodeParameters(wire).value)
