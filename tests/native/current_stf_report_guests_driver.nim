# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immediate available reports drive genuine guests, grouped operands and complete current-state publication.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/header
import ../../src/pvm/[initialize, machine]
import ../support/current_stf_epoch_context as epoch
import ../support/report_context as reportContext
import ../support/[current_stf_transfer_context, current_stf_lifecycle_context,
    current_stf_supervised_context, current_stf_privileges_context, current_stf_incarnation_context, current_stf_foreign_funding_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/[provider, genesis, parameters]
import ../../src/codec/[bounded, report_owned, block_codec, state_composition, state_accounts,
  state_requests, state_service_values, state_layout, state_safrole, composite]
import ../../src/crypto/primitives
import ../../src/state/safrole_transition
import ../../src/state/[store, checkpoint, accumulation_current_update,
  accumulation_current_completion,
  accumulation_current_driver, accumulation_current_round, accumulation_block_guests,
  accumulation_guest_runner, accumulation_dispatch, accumulation_invocation, report_admission,
  block_transition,
  guarantee_credentials,
  current_profile,
  current_globals, current_state, global_snapshot]
import ../support/[accumulation_execution_context, accumulation_activity_context,
  current_namespace_execution_context, current_namespace_context, current_consecutive_context,
  accumulation_current_chain_context,
  pvm_accumulation_program, pvm_accumulation_provision, state_inventory_context]

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
  if outcome.error == CurrentCandidateError.PrefixFailure:
    # Surface actual shared-prefix errors before report completion so a fixture ceiling is diagnosable.
    let prefix = outcome.prefixFailure
    result.add("/" & $prefix.error)
    if prefix.error == ApplicationCandidateError.BlockFailure:
      let transition = prefix.blockFailure
      result.add("/" & $transition.error)
      if transition.error == BlockTransitionError.SafroleFailure:
        let safrole = transition.safroleError
        result.add("/" & $safrole.error)
        if safrole.error == SafroleTransitionError.PublicationFailure: result.add("/" &
            $safrole.publicationError)
        if safrole.error == SafroleTransitionError.AuthenticationFailure: result.add("/" &
            $safrole.authenticationError)
    if prefix.error == ApplicationCandidateError.ReportFailure:
      let reports = prefix.reportFailure
      result.add("/" & $reports.error)
      if reports.error == ReportAdmissionError.PolicyFailure: result.add("/" & $reports.policyError)
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


proc fixtureCodes(mode: int, replacement: array[32, byte], codeLength: uint32, staging: seq[
    byte] = @[]): array[2, seq[byte]] =
  ## Keep literal family selection explicit and independent of the growing original/namespace construction workflow.
  var first = namespaceHaltCode()
  if mode in 113..117:
    first = precedenceAssignerCode(mode) # Both privileged actors execute from the same original role tuple.
  elif mode in 97..101:
    first = juniorConflictCode(mode) # The junior's own writes/yield/provision compete with its supervisor from one common prior.
  elif mode in 42..46:
    first = memoReceiverCode(mode) # Only memo recipients consume incoming bytes into storage and yields.
  elif mode in 15..19:
    first = forwardingCode(mode) # Only forwarding recipients create another outgoing record.
  var second: seq[byte] = @[]
  if mode in 161..165: first = allowanceManagerCode(mode,
      true) # The scheduled service is a real independently authored manager program.
  if mode in 171..175: first = incarnationRebindCode(
      mode) # Actual later self rebinding changes only the recorded supervisor incarnation.
  if mode in 176..182: first = foreignFundingJuniorCode() # A real parallel self-write competes with the selected foreign funding debit.
  case mode
  of 176..182: second = foreignCreationCode(mode, replacement,
      codeLength) # Exact original source authority chooses the funding pool.
  of 171..175: second = incarnationCreatorCode(mode, replacement,
      staging) # Exact known foreign-write bytes become the new77 code.
  of 166..170: second = allowanceEligibilityCode(mode) # Real zero/exact free budgets retain explicit dictionary membership.
  of 161..165: second = allowanceManagerCode(mode,
      false) # Original manager99 grants the future service its authority and allowance.
  of 155..160: second = blessAllowanceCode(mode) # Nonempty manager-selected dictionaries affect subsequent block inputs.
  of 148..154: second = childRecreationCode(mode, replacement,
      codeLength) # Real retirement clears the old incarnation before reserved-ID reuse.
  of 141..147: second = childRetirementCode(mode, replacement,
      codeLength) # Birth, cleanup, same-slot protection and later retirement share real invocations.
  of 136..140:
    second = preimageAgingCode(mode, array[32, byte](blake2b256([
        82'u8]).value)) # Strict age checks never narrow or wrap the invocation time.
  of 131..135:
    second = childReadinessCode(mode, replacement, namespaceHaltCode()) # The new public child becomes available only through selected fnprovide.
  of 123..130: second = reservedCreationCode(mode, replacement,
      codeLength) # Explicit nonzero deposits and registrar allocation.
  of 118..122: second = designationCode(mode, staging) # Staging publication becomes pending and then active across two epochs.
  of 113..117: second = precedenceManagerCode(mode) # GP R preserves the manager proposal only when it actually changes the old role.
  of 107..112: second = authorizationAssignCode(mode) # Real ordered queue replacement and original-assigner publication.
  of 102..106: second = supervisedHandoffCode(mode) # Foreign role assignment changes immediate authority but keeps prior-based M selection.
  of 97..101: second = supervisorConflictCode(mode) # Selected foreign membership drives real N/M decisions.
  of 92..96: second = supervisedUpgradeCode(mode, replacement) # Foreign metadata affects a later independently admitted42 report.
  of 87..91:
    # R's known hash selects one independently declared foreign request identity.
    let hash = array[32, byte](blake2b256([82'u8]).value)
    second = supervisedRequestCode(mode, hash)
  of 82..86: second = supervisedWriteCode(mode) # Genuine foreign storage publication, authority and exceptional selection.
  of 77..81: second = managerCode(mode) # One manager controls an unambiguous fixed-role handoff.
  of 72..76: second = ejectionCode(mode) # Empty old junior retirement and exact once-only refund.
  of 67..71:
    # A one-byte declared provision never aliases any code preimage or the original Q payload.
    let hash = array[32, byte](blake2b256([82'u8]).value)
    second = provisionCode(mode, hash)
  of 62..66:
    # R is a distinct one-byte payload identity, independent of code and the original I/Q reservations.
    let hash = array[32, byte](blake2b256([82'u8]).value)
    second = requestCode(mode, hash)
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
    uint32] = @[], reload = false) =
  ## Genuine authored code/request/namespace originals match the independent frozen inputs.
  let replacement = if mode in 171..175: supervisedWriteCode(82) elif mode in
      92..96: supervisedReplacementCode() else: namespaceHaltCode()
  let replacementHash = array[32, byte](blake2b256(replacement).value)
  let requestHash = ServicePreimageHash(array[32, byte](blake2b256([82'u8]).value))
  var staged: seq[byte] = @[]
  if mode in 171..175: staged = replacement # Whole child code is an explicit constructor input, not an observed successor.
  if mode in 118..122:
    # This maintained fixture authors the exact original ring-witness membership used independently by the reference.
    let source = epoch.original(base)
    let encoded = source.stateSnapshot.lookup(chapterKey(StateChapter(7))).value.bytes
    assert encoded.len == 2017 and encoded[0] == 6
    for index in 1..<encoded.len: staged.add(encoded[index])
  let codes = fixtureCodes(mode, replacementHash, uint32(replacement.len), staged)
  var seeds = namespaceSeeds()
  for index in 0..<2:
    let codeHash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
    seeds[index].requests.add(StateRequestItem(hash: codeHash, length: RequestLength(uint32(
        codes[index].len)), history: (if (missingCode and index == 1) or (mode == 170 and index ==
            0): requestedHistory(
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
  if mode in 92..96:
    # The foreign target reserves a distinct replacement identity before any block; missing-code mode never inserts its P value.
    let hash = ServicePreimageHash(replacementHash)
    seeds[0].requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(
        replacement.len)),
      history: (if mode == 95: requestedHistory() else: availableHistory(RequestSlot(1)))))
    if mode != 95: seeds[0].preimages.add(StatePreimageItem(hash: hash, value: replacement))
  if mode == 64 or mode in 67..71:
    # This original request must be removed before checkpointing and a later regular recreation is discarded.
    seeds[1].requests.add(StateRequestItem(hash: requestHash, length: RequestLength(1),
        history: requestedHistory()))
  if mode in 136..140:
    # R was genuinely supplied before removal; preserve its stored bytes at the exact boundary.
    seeds[1].requests.add(StateRequestItem(hash: requestHash, length: RequestLength(1),
      history: (if mode == 138: availableHistory(RequestSlot(0)) else: unavailableHistory(
          RequestSlot(0), RequestSlot(1)))))
    seeds[1].preimages.add(StatePreimageItem(hash: requestHash, value: @[82'u8]))
  if mode == 89:
    # Only the foreign forget-before-checkpoint original starts with R pending in42.
    seeds[0].requests.add(StateRequestItem(hash: requestHash, length: RequestLength(1),
        history: requestedHistory()))
  if mode in [1, 2]:
    seeds[1].storage.add(StateStorageItem(key: @[7'u8], value: (if mode == 1: @[
        1'u8, 2, 3, 4, 5] else: @[1'u8, 2]))) # Original replacement/deletion footprints are genuine parent inputs.
  var options = executionFixtureConfig()
  options.empty = true
  if mode == 170: options.first = ExecutionEnding.Missing # Genuine missing42 code retains its pending request and exact reservation.
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
  if mode in 155..170:
    options.manager = (if mode == 160: 42'u32 else: 99'u32) # Authority is committed before the first signed input.
  if mode in 77..81:
    # Authority belongs to one actual original manager; other roles and all allowances remain empty.
    options.manager = (if mode == 81: 42'u32 else: 99'u32)
  if mode in 82..106:
    # Authority is original and incarnation-bound; stale/missing nominees fall back to target self supervision.
    options.signed.accountSupervisor = (if mode == 86: 77'u32 else: 99'u32)
    options.signed.accountSupervisorCreated = (if mode in [85, 96, 101]: 1'u32 else: 0'u32)
  if mode in 107..112:
    options.assigner = 99 # Genuine original roles authorize both cores before any signed child.
  if mode in 113..117:
    options.assigner = 42 # Original assigner, not the later manager-selected role, supplies the queue.
    options.manager = 99
  if mode in 118..122:
    options.delegator = (if mode == 122: 42'u32 else: 99'u32) # A real original role determines selected staging authority.
  if mode in 123..130 or mode in 141..154:
    options.registrar = 99
    options.signed.accountBalance = 10000 # The other original account remains funded under the nonzero deposit profile.
    if mode in [124, 126, 142, 144, 149, 151]:
      options.secondBalance = 0
      options.secondSupervisorBalance = 1000000 # Protected source modes cannot borrow liquid funds.
    if mode == 130:
      # Original99 has two raw entries and four requests:10items and396+codeBytes; child threshold224 must preserve this own minimum.
      options.secondBalance = 566'u64+uint64(codes[1].len)+223'u64
  if mode in 171..175:
    options.registrar = 99
    options.signed.accountSupervisor = 77 # The original42 genuinely points to old77 creation0.
  if mode in 176..182:
    options.registrar = 99
    options.secondBalance = 10000
    options.signed.accountSupervisor = 99
    options.signed.accountSupervisorCreated = (if mode == 180: 1'u32 else: 0'u32)
    options.signed.accountBalance = (if mode in [177, 179]: 0'u64 else: 1000000'u64)
    options.signed.accountProtectedBalance = (if mode in [177,
        179]: 1000000'u64 else: 0'u64) # Only the selected foreign source pool is funded.
  options.signed.completeState = true
  options.signed.withTicket = true
  options.signed.serviceNamespaces = seeds
  options.signed.extra = @[activityParentEntry()]
  if mode in 72..76 or mode in 171..175:
    # No donor subkeys exist: this actual third account has zero footprint and both distinct funded pools.
    let donor = ServiceMetadata(balance: AccountBalance(7), supervisorBalance: AccountBalance(11),
      parent: ServiceIndex(99), supervisor: ServiceIndex(if mode == 75: 42 else: 99))
    options.signed.extra.add(serviceMetadataEntry(ServiceIndex(77), donor, ByteLimit(105)).value)
  let fixture = executionFixture(base, options)
  var chainParameters = currentChainSettings()
  if mode in 107..122 and mode != 112:
    # This authored larger-code profile admits the real queue-bearing program; mode112 retains512 as its eligibility control.
    var wire = chainParameters.encodeParameters
    for index in 0..<4: wire[98+index] = byte((4096'u32 shr (8*index)) and 255)
    chainParameters = decodeParameters(wire).value
  if mode in 136..140:
    # Explicit lookup age0 makes the pinned4800-slot safety margin observable with valid absolute uint32 slots.
    var wire = chainParameters.encodeParameters
    for index in 74..<78: wire[index] = 0
    chainParameters = decodeParameters(wire).value
  if mode in 123..130 or mode in 141..154 or mode in 176..182:
    # Author a distinct nonzero deposit schedule; existing zero-deposit profiles and all protocol checks remain intact.
    var wire = chainParameters.encodeParameters
    for field, value in [7'u64, 1'u64, 100'u64]:
      for index in 0..<8: wire[8*field+index] = byte((value shr (8*index)) and 255)
    chainParameters = decodeParameters(wire).value
  var chain = initApplicationChain(fixture.executionNamespaceParent(chainParameters)).value
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
  if mode in 57..61 or mode in 131..135:
    # At most two children extend the explicit two-account prior; later empty blocks retain all four canonical records.
    limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
  if mode in 62..71 or mode in 87..91 or mode in 136..140 or mode in 141..154:
    # One identity may be touched on both sides of a checkpoint; explicit observations retain the selected prefix.
    limits.completion.execution.initial.guests.requestFacts = ElementLimit(4)
    limits.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
  if mode in 67..71 or mode in 97..101:
    # One selected pair owns exactly one byte; union capture is explicit and shared by initial and continuation rounds.
    limits.completion.execution.initial.guests.provisions = provisionPolicy(items = 1, perBlob = 1, total = 1)
    limits.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
        perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
    limits.completion.execution.initial.provisions.encodedBytes = ByteLimit(32)
    limits.completion.execution.execution.round.guests.provisions = limits.completion.execution.initial.guests.provisions
    limits.completion.execution.execution.round.provisions = limits.completion.execution.initial.provisions
  if mode in 72..76:
    # Capture the complete three-account prior and one real retirement in both execution stages.
    limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.initial.guests.deletedAccounts = ElementLimit(1)
    limits.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(1)
  if mode in 107..122:
    # Whole code includes the actual2560-byte queue; bounded code/initialization/copy policies admit this exact authored size.
    limits.completion.composition.validators.preimageBytes = ByteLimit(4096)
    limits.completion.composition.activity.preimages.perBlob = ByteLimit(4096)
    limits.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(4096)
    limits.completion.composition.preimages.bytes = ByteLimit(4096)
    limits.completion.execution.initial.guests.preimageBytes = ByteLimit(4096)
    limits.completion.execution.initial.guests.initialization.envelope = InitializationByteLimit(4096)
    limits.completion.execution.initial.guests.copyBytes = MemoryByteLimit(2560)
    limits.completion.execution.execution.round.guests.preimageBytes = ByteLimit(4096)
    limits.completion.execution.execution.round.guests.initialization.envelope = InitializationByteLimit(4096)
    limits.completion.execution.execution.round.guests.copyBytes = MemoryByteLimit(2560)
  if mode in 123..130 or mode in 141..154 or mode in 176..182:
    # The complete prior may contain the one reserved child on later blocks; creation/debit facts keep their original bounds.
    limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
  if mode in 131..135:
    # One actual whole-code provision targets the just-created child, with exact input and union byte ceilings.
    limits.completion.execution.initial.guests.provisions = provisionPolicy(items = 1,
        perBlob = uint64(replacement.len), total = uint64(replacement.len))
    limits.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
        perBlob: ByteLimit(uint64(replacement.len)), totalBlobBytes: ByteLimit(uint64(
        replacement.len)))
    limits.completion.execution.initial.provisions.encodedBytes = ByteLimit(64)
    limits.completion.execution.execution.round.guests.provisions = limits.completion.execution.initial.guests.provisions
    limits.completion.execution.execution.round.provisions = limits.completion.execution.initial.provisions
  if mode in 141..154:
    # One real child may be retired; both initial and continuation passes retain exact deletion facts.
    limits.completion.execution.initial.guests.deletedAccounts = ElementLimit(1)
    limits.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(1)
  if mode in 171..175:
    # Full old/new77 inventory, one deletion/recreation and one exact code provision are explicit in both stages.
    limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
    limits.completion.execution.initial.guests.deletedAccounts = ElementLimit(1)
    limits.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(1)
    limits.completion.execution.initial.guests.provisions = provisionPolicy(items = 1,
        perBlob = uint64(replacement.len), total = uint64(replacement.len))
    limits.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
        perBlob: ByteLimit(uint64(replacement.len)), totalBlobBytes: ByteLimit(uint64(
        replacement.len)))
    limits.completion.execution.initial.provisions.encodedBytes = ByteLimit(512)
    limits.completion.execution.execution.round.guests.provisions = limits.completion.execution.initial.guests.provisions
    limits.completion.execution.execution.round.provisions = limits.completion.execution.initial.provisions
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
    if (mode in [57, 59, 60] or mode in 131..135) and uint32(before.slot) == 3:
      # Derive explicit namespace identities from posterior entropy and the authenticated slot; expected maps use separate Python equations.
      let encoded = snapshot.lookup(chapterKey(StateChapter(6))).value.bytes
      assert encoded.len == 128
      var entropy = default(array[32, byte])
      for index in 0..<32: entropy[index] = encoded[index]
      let initial = initialAccumulationService(ServiceIndex(99), StateEntropyWord(entropy),
          HeaderSlot(4))
      assert initial.error == AccumulationInvocationError.None
      if mode in 131..135:
        let born = snapshot.lookup(chapterServiceKey(StateChapter(255), initial.value))
        if born.error == StateStoreError.None: children.add(initial.value)
        else: assert born.error == StateStoreError.MissingKey # Exceptional rollback may discard this explicitly derived public child.
      else: children.add(initial.value)
      if mode == 60:
        # Public IDs occupy [65536,2^32-256); uint64 arithmetic proves the complete42-step addition before narrowing.
        let next = 65536'u64+(uint64(uint32(initial.value))-65536+42) mod 4294901504'u64
        children.add(ServiceIndex(uint32(next)))
      for service in children:
        assert before.stateSnapshot.lookup(chapterServiceKey(StateChapter(255), service)).error ==
            StateStoreError.MissingKey
    if mode in 123..130 or mode in 141..154 or mode in 171..182:
      # Reserved77 is a fixed authored identity at any absolute birth/retirement slot, including epoch-boundary recreation.
      children = @[]
      let stored = snapshot.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(77)))
      if stored.error == StateStoreError.None: children.add(ServiceIndex(77))
      else: assert stored.error == StateStoreError.MissingKey # A selected retirement or ordinary rollback leaves no declared child.
    var services = currentNamespaceServices(snapshot, seeds)
    if mode in 62..71 or mode in 87..91:
      # Materialize only the explicitly authored R identity, never infer arbitrary namespace entries from raw hashes.
      let target = if mode in 87..91: 0 else: 1
      let requestKey = serviceRequestKey(services[target].service, requestHash, RequestLength(1),
          ByteLimit(32)).value
      let stored = snapshot.lookup(requestKey)
      var declared = false
      for item in services[target].requests:
        if array[32, byte](item.hash) == array[32, byte](requestHash) and uint32(item.length) ==
            1: declared = true
      if stored.error == StateStoreError.None and not declared:
        services[target].requests.add(StateRequestItem(hash: requestHash, length: RequestLength(1),
            history: requestedHistory()))
      else: assert stored.error in [StateStoreError.None,
          StateStoreError.MissingKey] # Full-map comparison fixes presence independently.

    if mode in 67..71 or mode in 136..140:
      # Only R is newly provisionable; exact independent maps constrain its value and corresponding request history.
      let stored = snapshot.lookup(servicePreimageKey(ServiceIndex(99), requestHash, ByteLimit(32)).value)
      if mode in 136..140:
        var preserved: seq[StatePreimageItem] = @[]
        for item in services[1].preimages:
          if array[32, byte](item.hash) != array[32, byte](requestHash): preserved.add(
              item) # Keep all unrelated original identities.
        services[1].preimages = preserved
      if stored.error == StateStoreError.None:
        services[1].preimages.add(StatePreimageItem(hash: requestHash, value: @[82'u8]))
      else: assert stored.error == StateStoreError.MissingKey
    if mode in 97..101:
      # I is the junior's original pending payload; selected provision may survive annulment even when its writes/yield do not.
      let hash = ServicePreimageHash(array[32, byte](blake2b256([73'u8]).value))
      let stored = snapshot.lookup(servicePreimageKey(ServiceIndex(42), hash, ByteLimit(32)).value)
      if stored.error == StateStoreError.None:
        services[0].preimages.add(StatePreimageItem(hash: hash, value: @[73'u8]))
      else: assert stored.error == StateStoreError.MissingKey
    for index in 0..<2:
      # Original code/request identities remain explicit; unfulfilled payload requests stay untouched.
      let hash = ServicePreimageHash(array[32, byte](blake2b256(codes[index]).value))
      let codeKey = servicePreimageKey(services[index].service, hash, ByteLimit(32)).value
      let codeStored = snapshot.lookup(codeKey)
      if codeStored.error == StateStoreError.None:
        services[index].preimages.add(StatePreimageItem(hash: hash, value: codes[index]))
      else: assert ((missingCode and index == 1) or (mode == 170 and index == 0)) and
          codeStored.error == StateStoreError.MissingKey
      let declaredRequests = services[index].requests
      services[index].requests = @[]
      for originalItem in declaredRequests:
        # Fixed declared identities may be removed by a genuine selected forget; preserve every actual canonical history.
        let requestKey = serviceRequestKey(services[index].service, originalItem.hash,
            originalItem.length, ByteLimit(32)).value
        let stored = snapshot.lookup(requestKey)
        if stored.error == StateStoreError.None:
          let history = decodeRequestHistory(stored.value.bytes, RequestHistoryConfig(
              items: ElementLimit(3), maxBytes: ByteLimit(13)))
          assert history.error == RequestError.None
          var item = originalItem
          item.history = history.value.history
          services[index].requests.add(item)
        else:
          assert stored.error == StateStoreError.MissingKey # Unknown errors cannot masquerade as a selected request removal.
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
    if mode in 72..76:
      # The only extra declared identity is the authored empty junior; disappearance must be a real MissingKey.
      let stored = snapshot.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(77)))
      if stored.error == StateStoreError.None:
        let decoded = decodeServiceMetadata(stored.value.bytes, ByteLimit(105))
        assert decoded.error == ServiceMetadataError.None
        services.add(StateService(service: ServiceIndex(77), metadata: decoded.value.metadata))
      else: assert stored.error == StateStoreError.MissingKey
    for service in children:
      # New metadata and its sole empty code request remain independently constrained by the exact complete-map comparison.
      let value = snapshot.lookup(chapterServiceKey(StateChapter(255), service))
      if mode in 141..154 and value.error == StateStoreError.MissingKey:
        continue # A later genuine ejection removes this independently declared child, including all namespace keys.
      assert value.error == StateStoreError.None
      let metadata = decodeServiceMetadata(value.value.bytes, ByteLimit(105))
      assert metadata.error == ServiceMetadataError.None and metadata.value.consumed == 105
      if mode in 171..175 and (mode == 175 or uint32(before.slot) < 3):
        services.add(StateService(service: service, metadata: metadata.value.metadata))
        continue # The known original empty77 remains genuinely empty before creation or after creator rollback.
      let hash = ServicePreimageHash(replacementHash)
      let request = snapshot.lookup(serviceRequestKey(service, hash, RequestLength(uint32(
          replacement.len)), ByteLimit(32)).value)
      var declared = StateService(service: service, metadata: metadata.value.metadata, storage: @[],
          preimages: @[], requests: @[])
      if request.error == StateStoreError.None:
        let history = decodeRequestHistory(request.value.bytes, RequestHistoryConfig(
            items: ElementLimit(3), maxBytes: ByteLimit(13)))
        assert history.error == RequestError.None
        declared.requests.add(StateRequestItem(hash: hash, length: RequestLength(uint32(
            replacement.len)), history: history.value.history))
      else:
        assert mode in 141..154 and request.error ==
            StateStoreError.MissingKey # A selected forget removes the actual pending reservation.
      let preimage = snapshot.lookup(servicePreimageKey(service, hash, ByteLimit(32)).value)
      if preimage.error == StateStoreError.None: declared.preimages.add(StatePreimageItem(
          hash: hash, value: replacement))
      else: assert preimage.error == StateStoreError.MissingKey # Created code is unavailable until a genuine selected provision fulfills its request.
      services.add(declared)
    assert qualifyCurrentState(globals, services, inventoryCaptureLimits).error ==
        CurrentStateError.None
    assert checkpointHex(before.stateSnapshot) == saved
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    var next = @[before.header]
    for ancestor in ancestors: next.add(ancestor) # Retain actual selected ancestry for report lookup checks.
    ancestors = next
    if reload:
      # Decode into an independent full store, then recapture the exact selected header/profile before continuing admission.
      let selected = chain.chainView.bestBlock.value
      let encoded = encodeFullCheckpoint(selected.stateSnapshot, ByteLimit(100000))
      assert encoded.error == CheckpointError.None
      var checkpointPolicy = reportContext.limits()
      checkpointPolicy.writes = ElementLimit(options.signed.storeWrites)
      checkpointPolicy.writeValueBytes = ByteLimit(options.signed.maxWriteBytes)
      let restored = decodeFullCheckpoint(encoded.value, checkpointPolicy, ByteLimit(100000))
      assert restored.error == CheckpointError.None
      assert sameStateStorePolicy(selected.stateSnapshot, restored.value.snapshot.value)
      let captured = captureBlockSnapshot(currentChainBytes(selected.header),
          restored.value.snapshot.value, chainParameters)
      assert captured.error == GenesisError.None
      let view = genesisView(captured).finalizeView(captured.value.blockHash)
      assert view.error == ViewFinalizeError.None
      let reopened = initApplicationChain(view.value)
      assert reopened.error == ApplicationChainError.None
      chain = reopened.value
      assert checkpointHex(chain.stateSnapshot.value) == checkpointHex(selected.stateSnapshot)
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
  var reload = false
  var bodies: seq[seq[byte]] = @[]
  var slots: seq[uint32] = @[]
  for line in readFile(paramStr(2)).splitLines:
    if line.len == 0: continue # The final transport newline contains no request.
    let fields = line.splitWhitespace()
    assert fields.len in [2, 3]
    if fields[0] == "C":
      if mode >= 0: run(base, mode, bodies, missingCode,
          slots, reload) # Finish the complete chain before selecting another original.
      missingCode = fields.len == 3 and fields[2] == "missing"
      reload = fields.len == 3 and fields[2] == "reload"
      if fields.len == 3: assert missingCode or reload # Flags name an explicit original or full-store reconstruction contract.
      mode = parseInt(fields[1])
      assert mode >= 0 and mode < 183
      bodies = @[]
      slots = @[]
    else:
      assert fields[0] == "B" and mode >= 0
      slots.add(if fields.len == 3: uint32(parseInt(fields[1])) else: 0'u32)
      bodies.add(unhex(fields[^1]))
  assert bodies.len != 0 # Every selected chain must contain a signed child.
  assert reload or mode in [4, 9, 14, 19, 27, 41, 46, 51, 56, 61, 66, 71, 76, 81, 86, 91, 96, 101,
      106, 111, 112, 117, 122, 130, 135, 140, 147, 154, 160, 165, 170, 175, 182]
  run(base, mode, bodies, missingCode, slots, reload)

try:
  main() # I/O, compilation, guest, publication or qualification failure fails the complete corpus.
except:
  quit(2)
