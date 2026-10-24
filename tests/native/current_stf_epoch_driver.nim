# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current epoch/ticket chains use six distinct fixture scalars and immutable replayed RingVRF inputs.
import std/[assertions, algorithm, cmdline, strutils, parseutils, syncio]
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, block_codec, report_owned, state_layout, state_safrole,
  state_consensus, state_disputes, disputes, tickets, state_composition]
import ../../src/state/[store, checkpoint, accumulation_current_update, current_profile,
  current_globals, current_state, global_snapshot, block_transition, safrole_transition,
  safrole_markers, ticket_admission]
import ../../src/crypto/[primitives, extrinsic_commitment]
import ../../src/bandersnatch/bandersnatch
import ../support/[accumulation_current_chain_context, current_consecutive_context,
  current_namespace_context, state_inventory_context]

import ../support/current_stf_epoch_context

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
  main() # Each executable owns only its own corpus entry point; shared fixtures have no top-level work.
except:
  quit(2)
