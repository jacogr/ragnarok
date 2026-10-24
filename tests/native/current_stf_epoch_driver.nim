# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current epoch/ticket chains use six distinct fixture scalars and immutable replayed RingVRF inputs.
import std/[assertions, algorithm, cmdline, strutils, parseutils, syncio]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, block_codec, report_owned, state_layout, state_safrole,
  state_consensus, tickets, state_composition]
import ../../src/state/[store, checkpoint, accumulation_current_update, current_profile,
  current_globals, current_state, global_snapshot, block_transition, safrole_transition,
  safrole_markers, ticket_admission]
import ../../src/crypto/[primitives, extrinsic_commitment]
import ../../src/bandersnatch/bandersnatch
import ../support/[accumulation_current_chain_context, current_consecutive_context,
  current_namespace_context, state_inventory_context]

type BankTicket = object ## Public fixture scalars identify expected O/output equations; membership proofs remain native input witnesses.
  secret: int
  ticket: Ticket
  id: array[32, byte]

proc hex(bytes: openArray[byte]): string =
  ## Preserve every input/output octet for independent whole-map comparison.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())

proc unhex(text: string): seq[byte] =
  ## Trusted frozen fixture tokens still require exact even-width lowercase octets.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for index in 0..<result.len:
    var value: byte = 0
    assert parseHex(text[2*index..2*index+1], value) == 2
    result[index] = value

proc key(secret: int): BsKey =
  ## Only explicit public fixture scalars 1..6 are imported, never seeds or production secrets.
  assert secret in 1..6
  var scalar = default(array[32, byte])
  scalar[0] = byte(secret)
  importScalar(scalar).value

proc checkpointHex(state: StateStoreSnapshot): string =
  ## Full checkpoint bytes include every preserved global and supplied service namespace entry.
  hex(encodeFullCheckpoint(state, ByteLimit(100000)).value)

proc members(roster: openArray[StateValidator]): seq[byte] =
  ## Ring order is protocol data; preserve all six distinct authored ordinals.
  result = @[]
  for record in roster:
    for octet in array[32, byte](record.bandersnatch): result.add(octet)

proc original(base: OwnedReport): BlockSnapshot =
  ## Author a new complete initial map before child signing; existing fixture files/maps remain untouched.
  let context = currentChainFixture(base, completeState = true, serviceNamespaces = namespaceSeeds())
  let policy = currentConsecutiveLimits().reporting.safrole.state
  let captured = decodeStateValidators(context.parent.value.stateSnapshot.lookup(chapterKey(
      StateChapter(8))).value.bytes, policy.validators).value.value
  var active, pending, staging, previous = newSeq[StateValidator](6)
  for index in 0..<6:
    active[index] = validatorAt(captured, StateValidatorIndex(uint64(index))).value
    active[index].bandersnatch = StateBsKey(array[32, byte](publicKey(key(index+1)).value))
  for index in 0..<6:
    pending[index] = active[(index+1) mod 6]
    staging[index] = active[5-index]
    previous[index] = active[(index+2) mod 6]
  let setup = newSetup(6).value
  let root = StateRingRoot(array[144, byte](commitRing(setup, members(pending)).value))
  close(setup)
  var schedule = newSeq[StateBsKey](12)
  for index in 0..<12: schedule[index] = active[index mod 6].bandersnatch
  let consensus = safroleStateEntry(SafroleState(pending: pending, root: root,
      schedule: keySchedule(schedule), accumulator: @[]), policy).value
  var state = forkStateStore(context.parent.value.stateSnapshot).value
  var writes = @[StateWrite(key: consensus.key, kind: StateWriteKind.Put, value: consensus.value)]
  for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
    let records = if chapter == ValidatorChapter.Staging: staging
      elif chapter == ValidatorChapter.Active: active else: previous
    let entry = validatorEntry(chapter, records, policy.validators).value
    writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
  assert state.apply(writes).error == StateStoreError.None
  captureBlockSnapshot(currentChainBytes(context.parent.value.header), state.snapshot.value,
      currentChainSettings()).value

proc context(domain: string, seed: array[32, byte], attempt = -1): seq[byte] =
  ## Dollar-free domain octets, exact historical entropy and optional E1 attempt are never inferred from proof bytes.
  result = @[]
  for octet in domain: result.add(byte(octet))
  for octet in seed: result.add(octet)
  if attempt >= 0: result.add(byte(attempt))

proc compareTickets(a, b: BankTicket): int =
  ## Scores sort lexicographically by their exact 32 output bytes.
  for index in 0..<32:
    if a.id[index] < b.id[index]: return -1
    if a.id[index] > b.id[index]: return 1
  0

proc generate(parent: BlockSnapshot) =
  ## Explicit fixture generation uses the qualified native Ring prover; the normal corpus only replays fixed inputs.
  let policy = currentConsecutiveLimits().reporting.safrole.state
  let state = parent.stateSnapshot
  let prior = decodeSafroleState(state.lookup(chapterKey(StateChapter(4))).value.bytes,
      policy).value.snapshot
  let staging = decodeStateValidators(state.lookup(chapterKey(StateChapter(7))).value.bytes,
      policy.validators).value.value
  var rings = default(array[2, seq[StateValidator]])
  for index in 0..<6:
    rings[0].add(pendingValidatorAt(prior, StateValidatorIndex(uint64(index))).value)
    rings[1].add(validatorAt(staging, StateValidatorIndex(uint64(index))).value)
  let setup = newSetup(6).value
  echo "P ", checkpointHex(state)
  echo "R ", hex(array[144, byte](commitRing(setup, members(rings[1])).value))
  var bank: seq[BankTicket] = @[]
  for secret in 1..6:
    for attempt in 0..1:
      let transcript = context("jam_ticket_seal", default(array[32, byte]), attempt)
      let proof = signRing(setup, key(secret), (secret+4) mod 6, members(rings[0]), transcript, []).value
      let root = commitRing(setup, members(rings[0])).value
      bank.add(BankTicket(secret: secret, ticket: Ticket(attempt: TicketAttempt(byte(attempt)),
          proof: TicketProof(array[784, byte](proof))), id: array[32, byte](verifyRing(setup,
          root, proof, transcript, []).value)))
  bank.sort(compareTickets)
  for item in bank: echo "T ", item.secret, " ", byte(item.ticket.attempt), " ", hex(array[784,
      byte](item.ticket.proof))
  for secret in 1..2:
    let attempt = secret+1
    let transcript = context("jam_ticket_seal", default(array[32, byte]), attempt)
    let proof = signRing(setup, key(secret), 6-secret, members(rings[1]), transcript, []).value
    echo "T ", secret, " ", attempt, " ", hex(array[784, byte](proof))
  close(setup)

proc readBank(path: string): seq[BankTicket] {.raises.} =
  ## Frozen membership witnesses carry explicit public scalar/attempt attribution, not expected successor state.
  result = @[]
  for line in readFile(path).splitLines:
    if line.len == 0: continue # A final newline is transport framing only.
    let fields = line.splitWhitespace()
    assert fields.len == 3
    let secret = parseInt(fields[0])
    let attempt = parseInt(fields[1])
    let bytes = unhex(fields[2])
    assert bytes.len == 784 and attempt in 0..3
    var proof = default(array[784, byte])
    for index in 0..<784: proof[index] = bytes[index]
    let transcript = context("jam_ticket_seal", default(array[32, byte]), attempt)
    let thin = sign(key(secret), transcript, []).value
    let score = verify(publicKey(key(secret)).value, thin, transcript, []).value
    result.add(BankTicket(secret: secret, ticket: Ticket(attempt: TicketAttempt(byte(attempt)),
        proof: TicketProof(proof)), id: array[32, byte](score)))
  assert result.len == 14

proc zigzag(owner: SafroleStateSnapshot): seq[WinningTicket] =
  ## Outside-in ordering preserves each full identifier/attempt tuple.
  result = @[]
  for index in 0..<12:
    let at = if index mod 2 == 0: index div 2 else: 11-index div 2
    result.add(accumulatedTicketAt(owner, SafroleStateIndex(uint64(at))).value)

proc child(parent: BlockSnapshot, slot: uint32, submitted: seq[Ticket], bank: seq[BankTicket],
    damageMarker = false, damageWinners = false): OwnedBlock =
  ## Independently author native input headers from original roster/schedule data; actual candidate execution must validate them.
  let limits = currentConsecutiveLimits()
  let policy = limits.reporting.safrole.state
  let state = parent.stateSnapshot
  let prior = decodeSafroleState(state.lookup(chapterKey(StateChapter(4))).value.bytes,
      policy).value.snapshot
  let info = safroleInfo(prior).value
  let entropy = decodeStateEntropy(state.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  let crossed = slot div 12 > uint32(parent.slot) div 12
  var active, pending: seq[StateValidator] = @[]
  for index in 0..<6:
    active.add(if crossed: pendingValidatorAt(prior, StateValidatorIndex(uint64(index))).value
      else: validatorAt(decodeStateValidators(state.lookup(chapterKey(StateChapter(8))).value.bytes,
          policy.validators).value.value, StateValidatorIndex(uint64(index))).value)
    pending.add(if crossed: validatorAt(decodeStateValidators(state.lookup(chapterKey(StateChapter(
        7))).value.bytes, policy.validators).value.value, StateValidatorIndex(uint64(index))).value
      else: pendingValidatorAt(prior, StateValidatorIndex(uint64(index))).value)
  var ticketed = info.kind == SealerKind.Tickets
  var winning = default(WinningTicket)
  var public = default(array[32, byte])
  if crossed:
    ticketed = slot div 12 == uint32(parent.slot) div 12+1 and uint32(parent.slot) mod 12 >= 10 and
        info.accumulated == 12
    if ticketed:
      winning = zigzag(prior)[int(slot mod 12)]
    else:
      var message = context("", array[32, byte](entropy[1]))
      for index in 0..<4: message.add(byte(((slot mod 12) shr (8*index)) and 255))
      let hash = array[32, byte](blake2b256(message).value)
      var number = 0'u32
      for index in 0..<4: number = number or (uint32(hash[index]) shl (8*index))
      public = array[32, byte](active[int(number mod 6)].bandersnatch)
  elif ticketed:
    winning = sealerTicketAt(prior, SafroleStateIndex(uint64(slot mod 12))).value
  else:
    public = array[32, byte](sealerKeyAt(prior, SafroleStateIndex(uint64(slot mod 12))).value)
  var secret = 0
  if ticketed:
    for item in bank:
      if item.id == array[32, byte](winning.id): secret = item.secret
  else:
    for value in 1..6:
      if array[32, byte](publicKey(key(value)).value) == public: secret = value
  assert secret in 1..6
  let signer = key(secret)
  let signerPublic = array[32, byte](publicKey(signer).value)
  var author = -1
  for index, record in active:
    if array[32, byte](record.bandersnatch) == signerPublic: author = index
  assert author >= 0
  let transcript = context((if ticketed: "jam_ticket_seal" else: "jam_fallback_seal"),
      array[32, byte](entropy[if crossed: 2 else: 3]), (if ticketed: int(byte(
          winning.attempt)) else: -1))
  let provisional = sign(signer, transcript, []).value
  let output = verify(publicKey(signer).value, provisional, transcript, []).value
  var source = default(header.Header)
  source.unsigned.epoch = absentEpoch()
  if crossed:
    var pairs: seq[EpochValidator] = @[]
    for record in pending: pairs.add(EpochValidator(bandersnatch: HeaderBsKey(array[32, byte](
        record.bandersnatch)), ed25519: HeaderEdKey(array[32, byte](record.ed25519))))
    source.unsigned.epoch = presentEpoch(EpochEntropy(array[32, byte](entropy[0])),
        TicketsEntropy(array[32, byte](entropy[1])), pairs)
  if damageMarker: source.unsigned.epoch = absentEpoch() # The caller uses this only on a real epoch crossing.
  source.unsigned.winners = absentWinners()
  if not crossed and uint32(parent.slot) mod 12 < 10 and slot mod 12 >= 10 and info.accumulated == 12:
    source.unsigned.winners = presentWinners(zigzag(prior))
  if damageWinners: source.unsigned.winners = absentWinners() # A genuine cutoff requires the original saturated contest's marker.
  source.unsigned.parent = HeaderParent(array[32, byte](parent.blockHash))
  source.unsigned.priorState = PriorStateRoot(array[32, byte](state.commitment.root))
  source.unsigned.slot = HeaderSlot(slot)
  source.unsigned.author = AuthorIndex(uint16(author))
  source.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](sign(signer, context(
      "jam_entropy", array[32, byte](output)), []).value))
  var body = newSeq[byte](10000)
  let encoded = encodeTickets(submitted, TicketLimit(3), body)
  assert encoded.error == TicketError.None
  body.setLen(encoded.written)
  for index in 0..<6: body.add(0) # Empty preimages/guarantees/assurances and the three dispute lists.
  let extrinsic = decodeExtrinsic(body, limits.reporting.admission.frame).value.owner
  source.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(extrinsic,
      ByteLimit(10000)).value))
  let headerPolicy = limits.reporting.reports.ancestors.header
  var bytes = newSeq[byte](100000)
  let unsignedSize = encodeUnsignedHeader(source.unsigned, headerPolicy, bytes).value
  bytes.setLen(unsignedSize)
  source.seal = HeaderSeal(array[96, byte](sign(signer, transcript, bytes).value))
  bytes = newSeq[byte](100000)
  let written = encodeHeader(source, headerPolicy, bytes).value
  bytes.setLen(written)
  for octet in body: bytes.add(octet)
  decodeBlock(bytes, limits.reporting.admission.frame).value.owner

proc refused(chain: ApplicationChain, candidate: OwnedBlock,
    reason: TicketAdmissionError, marker = false, winners = false) =
  ## Exact nested refusals preserve the original complete map after every earlier private admission/rotation step.
  let saved = checkpointHex(chain.stateSnapshot.value)
  let outcome = prepareCurrentCandidate(chain, candidate, [], currentConsecutiveLimits())
  assert outcome.error == CurrentCandidateError.PrefixFailure
  assert outcome.prefixFailure.error == ApplicationCandidateError.BlockFailure
  let blockFailure = outcome.prefixFailure.blockFailure
  assert blockFailure.error == BlockTransitionError.SafroleFailure
  let safrole = blockFailure.safroleError
  if marker:
    assert safrole.error == SafroleTransitionError.MarkerFailure
    assert safrole.markerError == (if winners: SafroleMarkerError.InvalidWinnersMarker else: SafroleMarkerError.InvalidEpochMarker)
  else:
    assert safrole.error == SafroleTransitionError.AdmissionFailure
    assert safrole.admissionError == reason
  assert checkpointHex(chain.stateSnapshot.value) == saved

proc run(parent: BlockSnapshot, bank: seq[BankTicket], mode: int) =
  ## Three independently frozen paths distinguish saturated-tail tickets, skipped-tail fallback and incomplete-contest fallback.
  let captured = captureBlockSnapshot(currentChainBytes(parent.header), parent.stateSnapshot,
      currentChainSettings())
  var chain = initApplicationChain(genesisView(captured)).value
  let originalBytes = checkpointHex(parent.stateSnapshot)
  echo "P ", originalBytes
  let slots = if mode == 0: @[2'u32, 3, 4, 5, 10, 11, 12, 13, 36, 37]
    elif mode == 1: @[2'u32, 3, 4, 5, 12, 13] else: @[2'u32, 3, 10, 11, 12, 13]
  for slot in slots:
    var submitted: seq[Ticket] = @[]
    if slot in 2'u32..5'u32:
      for index in (int(slot)-2)*3..<(int(slot)-1)*3: submitted.add(bank[index].ticket)
    elif slot == 12: submitted.add(bank[12].ticket)
    elif slot == 13: submitted.add(bank[13].ticket)
    let before = chain.stateSnapshot.value
    let saved = checkpointHex(before)
    let selected = chain.chainView.bestBlock.value
    if mode == 0 and slot == 2:
      # Each correctly sealed hostile body isolates one protocol refusal before the genuine batch is admitted.
      refused(chain, child(selected, slot, @[bank[1].ticket, bank[0].ticket], bank),
          TicketAdmissionError.BadOrder)
      var attempt = bank[0].ticket
      attempt.attempt = TicketAttempt(4)
      refused(chain, child(selected, slot, @[attempt], bank), TicketAdmissionError.InvalidAttempt)
      var malformed = bank[0].ticket
      var proof = array[784, byte](malformed.proof)
      proof[300] = proof[300] xor 1
      malformed.proof = TicketProof(proof)
      refused(chain, child(selected, slot, @[malformed], bank), TicketAdmissionError.InvalidProof)
    if mode == 0 and slot == 3:
      refused(chain, child(selected, slot, @[bank[0].ticket], bank), TicketAdmissionError.Duplicate)
    if mode == 0 and slot == 10:
      refused(chain, child(selected, slot, @[bank[0].ticket], bank),
          TicketAdmissionError.UnexpectedTicket)
      refused(chain, child(selected, slot, submitted, bank, damageWinners = true),
          TicketAdmissionError.None, marker = true, winners = true)
    if slot == 12:
      refused(chain, child(selected, slot, submitted, bank, true), TicketAdmissionError.None, marker = true)
      if mode == 0:
        refused(chain, child(selected, slot, @[bank[0].ticket], bank),
            TicketAdmissionError.InvalidProof)
    let candidateBlock = child(selected, slot, submitted, bank)
    var bytes = newSeq[byte](candidateBlock.blockInfo.value.consumed)
    assert candidateBlock.encodeOwnedBlock(bytes).error == FrameError.None
    echo "B ", hex(bytes)
    let prepared = prepareCurrentCandidate(chain, candidateBlock, [], currentConsecutiveLimits())
    assert prepared.error == CurrentCandidateError.None, $prepared.error
    let update = prepared.value
    let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(1024),
        bytes: ByteLimit(65536))).value
    let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
        items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
    assert qualifyCurrentState(globals, currentNamespaceServices(update.currentUpdateState,
        namespaceSeeds()), inventoryCaptureLimits).error == CurrentStateError.None
    assert checkpointHex(before) == saved
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    echo "O ", checkpointHex(chain.stateSnapshot.value)
  assert checkpointHex(parent.stateSnapshot) == originalBytes

proc main() {.raises.} =
  ## Normal verification consumes fixed attributed proofs; generation is explicit and never runs from the corpus plan.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let parent = original(decodeOwnedReport(bytes, 2).value)
  if paramStr(2) == "--generate":
    generate(parent)
  else:
    let bank = readBank(paramStr(2))
    for mode in 0..<3: run(parent, bank, mode)

try:
  main() # I/O, credential or candidate failure cannot turn partial observations into passing whole-map evidence.
except:
  quit(2)
