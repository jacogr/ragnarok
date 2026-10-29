# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine preimage extrinsics and storage/yield/checkpoint guests produce complete current STF observations.
import std/[assertions, cmdline, strutils, syncio]
import ../../src/app/[chain, candidate]
import ../../src/chain/provider
import ../../src/codec/[bounded, report_owned, block_codec]
import ../../src/codec/state/[composition as state_composition, accounts as state_accounts,
    requests as state_requests, service_values as state_service_values]
import ../../src/crypto/primitives
import ../../src/state/[store, checkpoint]
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/state/current/[profile as current_profile, globals as current_globals,
    state as current_state]
import ../../src/state/global_snapshot
import ../support/[accumulation_execution_context, accumulation_activity_context,
  current_namespace_execution_context, current_namespace_context, current_consecutive_context,
  pvm_accumulation_program, state_inventory_context]

proc hex(bytes: openArray[byte]): string =
  ## Preserve exact checkpoint and signed-block octets for independent complete comparison.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())

proc checkpointHex(state: StateStoreSnapshot): string =
  ## Use the public complete-map storage envelope; the reference recomputes every root independently.
  let encoded = encodeFullCheckpoint(state, ByteLimit(100000))
  assert encoded.error == CheckpointError.None
  hex(encoded.value)

proc guest(mode: int): seq[byte] =
  ## Write raw key7, yield a visible commitment, then halt or panic with an optional real checkpoint.
  let value = if mode == 2: newSeq[byte](0) else: @[9'u8, 8, 7]
  var memory = newSeq[byte](64)
  memory[0] = 7
  for index, octet in value: memory[index+1] = octet
  for index in 0..<32: memory[index+32] = byte(index)
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, uint64(
        value.len)), @[10'u8, 5], registerImmediate(7, 196640), @[10'u8, 27]]
  if mode == 4: instructions.add(@[10'u8, 19]) # Exceptional selection must retain the actual checkpointed write/yield.
  instructions.add(if mode >= 3: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc run(base: OwnedReport, mode: int) =
  ## Every service/code/request enters the complete original parent before any tested child is signed.
  let codes = [namespaceHaltCode(), guest(mode)]
  var seeds = namespaceSeeds()
  for index in 0..<2:
    let codeHash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
    seeds[index].requests.add(StateRequestItem(hash: codeHash, length: RequestLength(uint32(
        codes[index].len)), history: availableHistory(RequestSlot(1))))
    let payload = @[byte(if index == 0: 73 else: 81)]
    seeds[index].requests.add(StateRequestItem(hash: ServicePreimageHash(array[32, byte](
        blake2b256(payload).value)), length: RequestLength(1), history: requestedHistory()))
  if mode in [1, 2]:
    seeds[1].storage.add(StateStorageItem(key: @[7'u8], value: (if mode == 1: @[
        1'u8, 2, 3, 4, 5] else: @[1'u8, 2]))) # Original replacement/deletion footprints are genuine parent inputs.
  var options = executionFixtureConfig()
  options.firstProgram = codes[0]
  options.secondProgram = codes[1]
  options.secondBalance = 1000000
  options.signed.completeState = true
  options.signed.withTicket = true
  options.signed.serviceNamespaces = seeds
  options.signed.extra = @[activityParentEntry()]
  let fixture = executionFixture(base, options)
  var chain = initApplicationChain(fixture.executionNamespaceParent).value
  let original = checkpointHex(chain.stateSnapshot.value)
  echo "P ", original
  let limits = currentConsecutiveLimits()
  # A second actual child repeats the guest effects after the first extrinsic fulfilled both requests.
  for index in 0..<2:
    let body = if index == 0: @[0'u8, 2, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 1, 81, 0, 0,
        0, 0, 0] else: newSeq[byte](7)
    let before = chain.stateSnapshot.value
    let retained = checkpointHex(before)
    if index == 0:
      # A correctly sealed late unsolicited preimage must refuse the whole candidate and preserve the original map.
      var invalid = body
      invalid[13] = 90 # Service99 requested Q, never Z; the earlier service42 preimage is valid.
      let rejected = prepareCurrentCandidate(chain, currentBodyChild(
          chain.chainView.bestBlock.value, invalid), [], limits)
      assert rejected.error == CurrentCandidateError.CompletionFailure, $rejected.error
      assert checkpointHex(chain.stateSnapshot.value) == retained
    let child = currentBodyChild(chain.chainView.bestBlock.value, body)
    var bytes = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(bytes).error == FrameError.None
    echo "B ", hex(bytes)
    let prepared = prepareCurrentCandidate(chain, child, [], limits)
    assert prepared.error == CurrentCandidateError.None, $prepared.error
    let update = prepared.value
    let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(
        1024), bytes: ByteLimit(65536))).value
    let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
        items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
    var services = currentNamespaceServices(update.currentUpdateState, seeds)
    for service in 0..<2:
      # Explicit source identities cover code and new extrinsic preimages; metadata comes from the selected actual map.
      let codeHash = ServicePreimageHash(array[32, byte](blake2b256(codes[service]).value))
      services[service].preimages.add(StatePreimageItem(hash: codeHash, value: codes[service]))
      let payload = @[byte(if service == 0: 73 else: 81)]
      let hash = ServicePreimageHash(array[32, byte](blake2b256(payload).value))
      services[service].preimages.add(StatePreimageItem(hash: hash, value: payload))
      services[service].requests[^1].history = availableHistory(RequestSlot(2))
    if mode == 0 or mode == 4:
      services[1].storage.add(StateStorageItem(key: @[7'u8], value: @[9'u8, 8, 7]))
    elif mode == 1:
      services[1].storage[^1].value = @[9'u8, 8, 7] # Replace the existing declared identity rather than append a duplicate.
    elif mode == 2:
      services[1].storage.setLen(services[1].storage.len-1) # A committed empty write deletes the key entirely.
    let qualified = qualifyCurrentState(globals, services, inventoryCaptureLimits)
    assert qualified.error == CurrentStateError.None, $qualified.error
    assert checkpointHex(before) == retained
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    echo "O ", checkpointHex(chain.stateSnapshot.value)
  assert checkpointHex(fixture.state.snapshot.value) == original

proc main() {.raises.} =
  ## Five explicit cases share frozen public report input, production libraries and checked candidate execution.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let base = decodeOwnedReport(bytes, 2).value
  for mode in 0..<5: run(base, mode)

try:
  main() # No partially printed chain is a passing corpus after I/O, guest or qualification refusal.
except:
  quit(2)
