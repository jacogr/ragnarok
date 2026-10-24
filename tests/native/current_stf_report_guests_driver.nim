# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immediate available reports drive genuine guests, grouped operands and complete current-state publication.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/header
import ../../src/app/[chain, candidate]
import ../../src/chain/provider
import ../../src/codec/[bounded, report_owned, block_codec, state_composition, state_accounts,
  state_requests, state_service_values]
import ../../src/crypto/primitives
import ../../src/state/[store, checkpoint, accumulation_current_update,
  accumulation_current_completion,
  accumulation_current_driver, accumulation_current_round, accumulation_block_guests,
  accumulation_guest_runner, accumulation_dispatch, current_profile,
  current_globals, current_state, global_snapshot]
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

proc failure(outcome: CurrentCandidateResult): string =
  ## Preserve selected typed completion reasons so a bounded fixture refusal cannot look like a map mismatch.
  result = $outcome.error
  if outcome.error == CurrentCandidateError.CompletionFailure:
    let completion = outcome.completionFailure
    result.add("/" & $completion.error)
    if completion.error == CurrentAccumulationCompletionError.SequenceFailure:
      let sequence = completion.sequenceFailure
      result.add("/" & $sequence.error)
      if sequence.error == CurrentSequenceDriverError.InitialFailure:
        let initial = sequence.initialFailure
        result.add("/" & $initial.error)
        if initial.error == CurrentAccumulationRoundError.GuestFailure:
          let blockGuests = initial.guestFailure
          result.add("/" & $blockGuests.error)
          if blockGuests.error == BlockGuestError.GuestFailure:
            let guests = blockGuests.guestFailure
            result.add("/" & $guests.error)
            case guests.error
            of AccumulationGuestError.InvocationFailure: result.add("/" & $guests.invocationFailure)
            of AccumulationGuestError.ContextFailure: result.add("/" & $guests.contextFailure)
            of AccumulationGuestError.DispatchFailure: result.add("/" &
                $guests.dispatchFailure.error)
            of AccumulationGuestError.ServiceFailure: result.add("/" & $guests.serviceFailure)
            else: discard # Other actual typed guest failures retain their direct reason.


proc run(base: OwnedReport, mode: int, bodies: seq[seq[byte]]) =
  ## Genuine authored code/request/namespace originals match the independent frozen inputs.
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
  options.empty = true
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
  var limits = currentConsecutiveLimits()
  limits.completion.composition.validators.projection.assurances = ElementLimit(6)
  limits.completion.composition.validators.projection.reporters = ElementLimit(6)
  limits.completion.composition.validators.projection.comparisons = ElementLimit(36)
  limits.completion.composition.activity.available = ElementLimit(2)
  limits.completion.composition.activity.assurances = ElementLimit(6)
  # Two real report operands carry five-byte authorization traces and two-byte successful outputs.
  limits.completion.execution.initial.guests.fetch.items = ElementLimit(2)
  limits.completion.execution.initial.guests.fetch.bytes = ByteLimit(1024)
  limits.completion.execution.initial.guests.fetch.operand.outputBytes = ByteLimit(2)
  limits.completion.execution.initial.guests.fetch.operand.authBytes = ByteLimit(5)
  limits.completion.execution.initial.guests.fetch.operand.totalBlobBytes = ByteLimit(7)
  # Continuation dispatch captures the same bounded report payloads after the first affordable prefix.
  limits.completion.execution.execution.round.guests.fetch = limits.completion.execution.initial.guests.fetch
  # One release resolves five authored reports across two batches, all retained in one processed row.
  limits.completion.composition.statistics.operands = ElementLimit(5)
  limits.completion.composition.finalization.history.reports = ElementLimit(5)
  limits.completion.composition.finalization.history.queues.perSlot = ElementLimit(5)
  var ancestors: seq[OwnedHeader] = @[]
  for body in bodies:
    # Exact independent extrinsics enter a real seal against the selected canonical parent.
    let before = chain.chainView.bestBlock.value
    let saved = checkpointHex(before.stateSnapshot)
    let child = currentSameEpochBodyChild(before, body)
    var wire = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(wire).error == FrameError.None
    echo "B ", hex(wire)
    let prepared = prepareCurrentCandidate(chain, child, ancestors, limits)
    assert prepared.error == CurrentCandidateError.None, failure(prepared)
    let update = prepared.value
    let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(
        1024), bytes: ByteLimit(65536))).value
    let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
        items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
    let snapshot = update.currentUpdateState
    var services = currentNamespaceServices(snapshot, seeds)
    for index in 0..<2:
      # Original code/request identities remain explicit; unfulfilled payload requests stay untouched.
      let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
      services[index].preimages.add(StatePreimageItem(hash: hash, value: codes[index]))
    let storageKey = serviceStorageKey(ServiceIndex(99), @[7'u8], ByteLimit(32)).value
    let stored = snapshot.lookup(storageKey)
    services[1].storage = @[]
    for item in seeds[1].storage:
      if item.key != @[7'u8]: services[1].storage.add(item) # Preserve all other declared original identities.
    if stored.error == StateStoreError.None:
      services[1].storage.add(StateStorageItem(key: @[7'u8], value: stored.value.bytes))
    else:
      assert stored.error == StateStoreError.MissingKey # Deletion/rollback does not fabricate an empty stored value.
    assert qualifyCurrentState(globals, services, inventoryCaptureLimits).error ==
        CurrentStateError.None
    assert checkpointHex(before.stateSnapshot) == saved
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    var next = @[before.header]
    for ancestor in ancestors: next.add(ancestor) # Retain actual selected ancestry for report lookup checks.
    ancestors = next
    echo "O ", checkpointHex(chain.stateSnapshot.value)
  assert checkpointHex(fixture.state.snapshot.value) == original

proc unhex(value: string): seq[byte] =
  ## Decode only the canonical test transport; production decoders still validate its complete bodies.
  assert value.len mod 2 == 0
  result = newSeq[byte](value.len div 2)
  for index in 0..<result.len:
    var octet: byte = 0
    assert parseHex(value[2*index..2*index+1], octet) == 2
    result[index] = octet

proc main() {.raises.} =
  ## Authored independent chains use checked production libraries and fail on any partial run.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let base = decodeOwnedReport(bytes, 2).value
  var mode = -1
  var bodies: seq[seq[byte]] = @[]
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final transport newline contains no request.
    let fields = line.splitWhitespace()
    assert fields.len == 2
    if fields[0] == "C":
      if mode >= 0: run(base, mode, bodies) # Finish the complete chain before selecting another original.
      mode = parseInt(fields[1])
      assert mode >= 0 and mode < 5
      bodies = @[]
    else:
      assert fields[0] == "B" and mode >= 0
      bodies.add(unhex(fields[1]))
  assert mode == 4 and bodies.len == 7
  run(base, mode, bodies)

try:
  main() # I/O, compilation, guest, publication or qualification failure fails the complete corpus.
except:
  quit(2)
