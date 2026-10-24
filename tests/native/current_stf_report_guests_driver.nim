# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immediate available reports drive genuine guests, grouped operands and complete current-state publication.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/header
import ../support/current_stf_epoch_context as epoch
import ../support/[current_stf_transfer_context, current_stf_lifecycle_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/provider
import ../../src/codec/[bounded, report_owned, block_codec, state_composition, state_accounts,
  state_requests, state_service_values, state_layout, state_safrole]
import ../../src/crypto/primitives
import ../../src/state/[store, checkpoint, accumulation_current_update,
  accumulation_current_completion,
  accumulation_current_driver, accumulation_current_round, accumulation_block_guests,
  accumulation_guest_runner, accumulation_dispatch, accumulation_invocation, report_admission,
  guarantee_credentials,
  current_profile,
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
  if outcome.error == CurrentCandidateError.ReportFailure:
    let reports = outcome.reportFailure
    result.add("/" & $reports.error)
    case reports.error
    of ReportAdmissionError.CredentialFailure: result.add("/" & $reports.credentialError.error)
    of ReportAdmissionError.PolicyFailure: result.add("/" & $reports.policyError)
    of ReportAdmissionError.AnchorFailure: result.add("/" & $reports.anchorError)
    of ReportAdmissionError.PackageFailure: result.add("/" & $reports.packageError)
    of ReportAdmissionError.AssignmentFailure: result.add("/" & $reports.assignmentError)
    else: discard # Preserve the selected report-level refusal without inspecting unrelated payloads.
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


proc fixtureCodes(mode: int, replacement: array[32, byte], codeLength: uint32): array[2, seq[byte]] =
  ## Keep literal family selection explicit and independent of the growing original/namespace construction workflow.
  var first = namespaceHaltCode()
  if mode in 42..46:
    first = memoReceiverCode(mode) # Only memo recipients consume incoming bytes into storage and yields.
  elif mode in 15..19:
    first = forwardingCode(mode) # Only forwarding recipients create another outgoing record.
  var second: seq[byte] = @[]
  case mode
  of 57..61: second = creationCode(mode, replacement,
      codeLength) # Current new20 and real child cursor progression.
  of 52..56: second = supervisorCode(mode) # Self-supervisor mutation precedes protected funding.
  of 47..51: second = upgradeCode(mode, replacement) # Old/replacement code are separate original namespace identities.
  of 42..46: second = memoSenderCode() # Every fixed memo octet has a distinct explicit value.
  of 28..41: second = admissionTransferCode(mode) # Endpoint, memory, funding and gas boundaries.
  of 20..27: second = poolTransferCode(mode) # All four funding/credit pool combinations.
  of 5..19: second = transferCode(mode) # Initial transfer/forwarding/supervision families share literal source code.
  else: second = guest(mode) # Earlier storage/report guest originals retain their exact code bytes.
  result = [first, second]


proc run(base: OwnedReport, mode: int, bodies: seq[seq[byte]], missingCode = false, slots: seq[
    uint32] = @[]) =
  ## Genuine authored code/request/namespace originals match the independent frozen inputs.
  let replacement = namespaceHaltCode()
  let replacementHash = array[32, byte](blake2b256(replacement).value)
  let codes = fixtureCodes(mode, replacementHash, uint32(replacement.len))
  var seeds = namespaceSeeds()
  for index in 0..<2:
    let codeHash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
    seeds[index].requests.add(StateRequestItem(hash: codeHash, length: RequestLength(uint32(
        codes[index].len)), history: (if missingCode and index == 1: requestedHistory(
      ) else: availableHistory(RequestSlot(1)))))
    let payload = @[byte(if index == 0: 73 else: 81)]
    seeds[index].requests.add(StateRequestItem(hash: ServicePreimageHash(array[32, byte](
        blake2b256(payload).value)), length: RequestLength(1), history: requestedHistory()))
  if mode in 47..51:
    # Replacement code is reserved in the original99 namespace; missing-target mode never fabricates its preimage.
    let hash = ServicePreimageHash(replacementHash)
    seeds[1].requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(
        replacement.len)),
      history: (if mode == 50: requestedHistory() else: availableHistory(RequestSlot(1)))))
    if mode != 50: seeds[1].preimages.add(StatePreimageItem(hash: hash, value: replacement))
  if mode in [1, 2]:
    seeds[1].storage.add(StateStorageItem(key: @[7'u8], value: (if mode == 1: @[
        1'u8, 2, 3, 4, 5] else: @[1'u8, 2]))) # Original replacement/deletion footprints are genuine parent inputs.
  var options = executionFixtureConfig()
  options.empty = true
  if missingCode: options.second = ExecutionEnding.Missing # Code is honestly absent until a requested preimage extrinsic fulfills it.
  options.firstProgram = codes[0]
  options.secondProgram = codes[1]
  options.secondBalance = 1000000
  if mode >= 5: options.signed.accountTransferGas = 10 # Explicit transfer originals admit the paid recipient invocation.
  if mode in 10..14:
    # Incarnation-bound supervision is committed in the original metadata before any signed child.
    options.signed.accountSupervisor = (if mode == 13: 77'u32 elif mode == 14: 42'u32 elif mode in [
        11, 12]: 99'u32 else: 0'u32)
    options.signed.accountSupervisorCreated = (if mode == 12: 1'u32 else: 0'u32)
  if mode in 20..27:
    # Protected-source originals have no liquid funding, proving the selected source pool independently.
    if (mode-20) mod 4 in [1, 3]:
      options.secondBalance = 0
      options.secondSupervisorBalance = 1000000
    if mode >= 24: options.signed.accountSupervisor = 99 # Direct credit requires actual destination authority.
  if mode in 52..56:
    # Actual protected-only funds make the post-reassignment authority check distinguishable from ordinary funding.
    options.secondBalance = 0
    options.secondSupervisorBalance = 1000000
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
  # Whole guest-code preimages retain explicit byte limits independent of operand payload bounds.
  limits.completion.composition.validators.preimageBytes = ByteLimit(512)
  limits.completion.composition.activity.preimages.perBlob = ByteLimit(512)
  limits.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(512)
  limits.completion.composition.preimages.bytes = ByteLimit(512)
  if mode in 57..61:
    # At most two children extend the explicit two-account prior; later empty blocks retain all four canonical records.
    limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
  var children: seq[ServiceIndex] = @[]
  var ancestors: seq[OwnedHeader] = @[]
  for bodyIndex, body in bodies:
    # Exact independent extrinsics enter a real seal against the selected canonical parent.
    let before = chain.chainView.bestBlock.value
    let saved = checkpointHex(before.stateSnapshot)
    let child = if slots.len > 0 and slots[bodyIndex] > 0:
      epoch.child(before, slots[bodyIndex], @[], @[], limits = limits, bodyWire = body)
    else: currentSameEpochBodyChild(before, body) # Original consecutive same-epoch cases keep their exact constructor.
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
    if mode in [57, 59, 60] and uint32(before.slot) == 3:
      # Derive explicit namespace identities from posterior entropy and the authenticated slot; expected maps use separate Python equations.
      let encoded = snapshot.lookup(chapterKey(StateChapter(6))).value.bytes
      assert encoded.len == 128
      var entropy = default(array[32, byte])
      for index in 0..<32: entropy[index] = encoded[index]
      let initial = initialAccumulationService(ServiceIndex(99), StateEntropyWord(entropy),
          HeaderSlot(4))
      assert initial.error == AccumulationInvocationError.None
      children.add(initial.value)
      if mode == 60:
        # Public IDs occupy [65536,2^32-256); uint64 arithmetic proves the complete42-step addition before narrowing.
        let next = 65536'u64+(uint64(uint32(initial.value))-65536+42) mod 4294901504'u64
        children.add(ServiceIndex(uint32(next)))
      for service in children:
        assert before.stateSnapshot.lookup(chapterServiceKey(StateChapter(255), service)).error ==
            StateStoreError.MissingKey
    var services = currentNamespaceServices(snapshot, seeds)
    for index in 0..<2:
      # Original code/request identities remain explicit; unfulfilled payload requests stay untouched.
      let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
      let codeKey = servicePreimageKey(services[index].service, hash, ByteLimit(32)).value
      let codeStored = snapshot.lookup(codeKey)
      if codeStored.error == StateStoreError.None:
        services[index].preimages.add(StatePreimageItem(hash: hash, value: codes[index]))
      else: assert missingCode and index == 1 and codeStored.error == StateStoreError.MissingKey
      for ordinal in 0..<services[index].requests.len:
        # Declared identities are fixed; actual canonical histories must match the full candidate map.
        let item = services[index].requests[ordinal]
        let requestKey = serviceRequestKey(services[index].service, item.hash, item.length,
            ByteLimit(32)).value
        let history = decodeRequestHistory(snapshot.lookup(requestKey).value.bytes,
            RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
        assert history.error == RequestError.None
        services[index].requests[ordinal].history = history.value.history
    for index in 0..<2:
      # Both explicit services may write raw key7; all other original namespace identities remain declared.
      let service = ServiceIndex(if index == 0: 42 else: 99)
      let storageKey = serviceStorageKey(service, @[7'u8], ByteLimit(32)).value
      let stored = snapshot.lookup(storageKey)
      services[index].storage = @[]
      for item in seeds[index].storage:
        if item.key != @[7'u8]: services[index].storage.add(
            item) # Preserve every unrelated original storage identity.
      if stored.error == StateStoreError.None:
        services[index].storage.add(StateStorageItem(key: @[7'u8], value: stored.value.bytes))
      else:
        assert stored.error == StateStoreError.MissingKey # Deletion/rollback cannot fabricate an empty stored value.
    for service in children:
      # New metadata and its sole empty code request remain independently constrained by the exact complete-map comparison.
      let value = snapshot.lookup(chapterServiceKey(StateChapter(255), service))
      assert value.error == StateStoreError.None
      let metadata = decodeServiceMetadata(value.value.bytes, ByteLimit(105))
      assert metadata.error == ServiceMetadataError.None and metadata.value.consumed == 105
      services.add(StateService(service: service, metadata: metadata.value.metadata, storage: @[],
          preimages: @[],
        requests: @[StateRequestItem(hash: ServicePreimageHash(replacementHash),
            length: RequestLength(uint32(replacement.len)), history: requestedHistory())]))
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
  var missingCode = false
  var bodies: seq[seq[byte]] = @[]
  var slots: seq[uint32] = @[]
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final transport newline contains no request.
    let fields = line.splitWhitespace()
    assert fields.len in [2, 3]
    if fields[0] == "C":
      if mode >= 0: run(base, mode, bodies, missingCode,
          slots) # Finish the complete chain before selecting another original.
      missingCode = fields.len == 3
      if missingCode: assert fields[2] == "missing" # Explicit authored missing-code original.
      mode = parseInt(fields[1])
      assert mode >= 0 and mode < 62
      bodies = @[]
      slots = @[]
    else:
      assert fields[0] == "B" and mode >= 0
      slots.add(if fields.len == 3: uint32(parseInt(fields[1])) else: 0'u32)
      bodies.add(unhex(fields[^1]))
  assert mode in [4, 9, 14, 19, 27, 41, 46, 51, 56, 61] and bodies.len >
      0 # Strict independent output comparison binds each complete chain length.
  run(base, mode, bodies, missingCode, slots)

try:
  main() # I/O, compilation, guest, publication or qualification failure fails the complete corpus.
except:
  quit(2)
