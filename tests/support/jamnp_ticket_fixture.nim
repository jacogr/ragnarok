# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Six independently signed RingVRF fixture members produce an exact complete-map finalized-context witness.
import std/assertions
import ./jamnp_topology_fixture
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, tickets]
import ../../src/codec/state/[safrole, consensus, layout, trie]
import ../../src/state/store
import ../../src/bandersnatch/bandersnatch
import ../../src/jamnp-s/ticket_packet

type
  TicketFixture* = object ## Only public proof/source facts escape; private signing/setup owners retire before return.
    saved*: BlockSnapshotResult
    packet*: TicketPacket
    output*: WinningTicketId
    proxyIndex*: int
proc ticketFixture*(local, peer: StateEdKey, distribution = false,
    entropyChanged = false, included = false, atSlot = 1'u32,
    neighbour = default(StateEdKey), hasNeighbour = false): TicketFixture =
  ## Literal GP context construction is independent of the production network verifier.
  var keys = newSeq[BsKey](6)
  var pending = topologyRecords(2, 6)
  var members: seq[byte] = @[]
  for index in 0..<6:
    var seed = default(array[32, byte])
    seed[0] = byte(index+1)
    let made = importSecretSeed(seed)
    assert made.error == BsError.None
    keys[index] = made.value
    let public = publicKey(keys[index])
    assert public.error == BsError.None
    let raw = array[32, byte](public.value)
    pending[index].bandersnatch = StateBsKey(raw)
    for octet in raw: members.add(octet)
  let setup = newSetup(6)
  assert setup.error == BsError.None
  let committed = commitRing(setup.value, members)
  assert committed.error == BsError.None
  var context = default(array[48, byte])
  for index, character in "jam_ticket_seal": context[index] = byte(character)
  let signed = signRing(setup.value, keys[2], 2, members, context, [])
  assert signed.error == BsError.None
  let verified = verifyRing(setup.value, committed.value, signed.value, context, [])
  assert verified.error == BsError.None
  let output = array[32, byte](verified.value)
  let selector = uint64(output[28])*16777216+uint64(output[29])*65536+uint64(output[30])*256+uint64(
      output[31])
  let selected = int(selector mod 6)
  pending[selected].ed25519 = if distribution: peer else: local
  var current = topologyRecords(1, 6)
  current[0].ed25519 = peer
  current[1].ed25519 = local
  if hasNeighbour:
    let position = if selected == 4: 2 else: 4
    current[position].ed25519 = neighbour # Neither the local current row/column nor its next-epoch proxy ordinal.
  let base = topologyCaptured([topologyRecords(0, 6), current, pending], cores = 2, atSlot = atSlot)
  assert base.error == GenesisError.None
  var entries: seq[StateEntry] = @[]
  for index in 0..<base.value.keyCount:
    let key = base.value.keyAt(StateKeyIndex(index))
    if array[31, byte](key) != array[31, byte](chapterKey(StateChapter(4))):
      entries.add(StateEntry(key: key, value: base.value.lookup(key).value.bytes))
  let accumulated = if included: @[WinningTicket(id: WinningTicketId(output),
      attempt: TicketAttempt(0))] else: newSeq[WinningTicket](0)
  let chapter = safroleStateEntry(SafroleState(pending: pending,
      root: StateRingRoot(array[144, byte](committed.value)),
      schedule: keySchedule(newSeq[StateBsKey](12)), accumulator: accumulated), topologyLimits(2))
  assert chapter.error == StateComponentError.None
  entries.add(chapter.value)
  var entropy = default(StateEntropy)
  if entropyChanged:
    var word = default(array[32, byte])
    word[0] = 1
    entropy[2] = StateEntropyWord(word) # The otherwise valid proof was signed over all-zero entropy.
  entries.add(entropyEntry(entropy))
  var wire = newSeq[byte](base.value.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(base.value.header, wire).error == HeaderError.None
  let saved = captureBlockSnapshot(wire, entries, topologySettings(2))
  assert saved.error == GenesisError.None
  let packet = ticketPacket(TicketEpoch(1), Ticket(attempt: TicketAttempt(0), proof: TicketProof(
      array[784, byte](signed.value))))
  assert packet.error == TicketPacketError.None
  TicketFixture(saved: saved, packet: packet.value, output: WinningTicketId(output),
      proxyIndex: selected)
