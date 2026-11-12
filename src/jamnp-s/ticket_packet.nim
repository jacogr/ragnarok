# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact fixed CE131/132 payloads remain untrusted until finality-bound RingVRF and recipient verification.

import ../codec/tickets

type
  TicketEpoch* = distinct uint32 ## The E4 index identifies the use epoch, not the distribution epoch or a timeslot.
  TicketDelivery* {.pure.} = enum ## Both messages have identical bytes but different authenticated recipient contracts.
    Proxy, Distribution
  TicketPacketError* {.pure.} = enum ## Defaults and failures expose no proof or epoch prefix.
    Uninitialized, None, InvalidLength, InvalidAttempt
  TicketPacket* = object ## Private fixed copied facts contain no borrowed wire buffer or cryptographic authority.
    ready: bool
    epoch: TicketEpoch
    ticket: Ticket
  TicketPacketResult* = object ## Full exact decoding alone exposes the untrusted fixed packet.
    case status: TicketPacketError
    of None: completed: TicketPacket
    else: discard              # A short proof cannot become a valid all-zero suffix.

const TicketPacketBytes* = 789 ## E4 use epoch, E1 attempt and exactly784 proof bytes.

func error*(outcome: TicketPacketResult): TicketPacketError =
  ## Inspect parsing without extracting a default proof.
  outcome.status

func value*(outcome: TicketPacketResult): TicketPacket {.requires: outcome.status ==
    TicketPacketError.None.} =
  ## Exact wire shape remains separate from proof validity.
  outcome.completed

func valid*(packet: TicketPacket): bool =
  ## Defaults cannot enter verification or outbound scheduling.
  packet.ready

func epoch*(packet: TicketPacket): TicketEpoch {.requires: packet.ready.} =
  ## Return the untrusted nominal use epoch by value.
  packet.epoch

func ticket*(packet: TicketPacket): Ticket {.requires: packet.ready.} =
  ## All proof bytes are copied; this extraction is not a verified-ticket certificate.
  packet.ticket

proc decodeTicketPacket*(input: openArray[byte]): TicketPacketResult =
  ## Pinned JAMNP-S attempts are0/1 even when a nonstandard GP profile allows a larger local attempt ceiling.
  if input.len != TicketPacketBytes: return TicketPacketResult(
      status: TicketPacketError.InvalidLength)
  if input[4] > 1: return TicketPacketResult(status: TicketPacketError.InvalidAttempt)
  var epoch = 0'u32
  for index in 0..<4: epoch = epoch or (uint32(input[index]) shl (index*8))
  var proof = default(array[784, byte])
  for index in 0..<784: proof[index] = input[5+index]
  TicketPacketResult(status: TicketPacketError.None, completed: TicketPacket(ready: true,
      epoch: TicketEpoch(epoch), ticket: Ticket(attempt: TicketAttempt(input[4]),
          proof: TicketProof(proof))))

proc packetBytes*(packet: TicketPacket): array[TicketPacketBytes, byte] {.requires: packet.ready.} =
  ## The outer route owns selector/E4/FIN; no count or alternative epoch encoding is appended here.
  result = default(array[TicketPacketBytes, byte])
  for index in 0..<4: result[index] = byte((uint32(packet.epoch) shr (index*8)) and 255)
  result[4] = byte(packet.ticket.attempt)
  let proof = array[784, byte](packet.ticket.proof)
  for index in 0..<784: result[5+index] = proof[index]

proc ticketPacket*(epoch: TicketEpoch, ticket: Ticket): TicketPacketResult =
  ## Locally provided proofs use the same single network attempt domain and exact decoder.
  let packet = TicketPacket(ready: true, epoch: epoch, ticket: ticket)
  decodeTicketPacket(packet.packetBytes)
