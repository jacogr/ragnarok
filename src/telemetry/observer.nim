# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Translate transport observations into bounded JIP-3 events.
##
## Incoming handshake slots correlate TLS start and outcome through SSL destruction.
## The separate admitted-peer table retains copied certificate identities until a close
## is observed. TLS success can precede a capacity refusal, so it cannot establish that a
## peer was admitted. Keeping the tables separate lets a handshake observation be dropped
## without assigning an unrelated identity to a later close.
##
## The exporter and callback tables outlive native teardown. Overflow or missing metadata
## accounts for dropped observations without changing admission. Callbacks copy usable
## borrowed data before returning and only queue frames.

import std/[times, monotimes]
import ./[wire, client]
import ../quic/[transport, address]
export wire, client

proc eventTimestamp(): Timestamp =
  ## Convert wall time to the wire epoch; zero denotes an unavailable/pre-epoch local clock.
  let wall = getTime()
  let seconds = wall.toUnix - 1_735_732_800'i64
  if seconds < 0 or seconds > int64(high(uint64) div 1_000_000) - 1:
    return Timestamp(0) # Do not narrow or wrap an unrepresentable local timestamp.
  Timestamp(uint64(seconds) * 1_000_000 + uint64(wall.nanosecond div 1000))

proc observe*(client: var Client, peers: uint32) =
  ## Translate wall time for wire timestamps and monotonic time for retry/status deadlines.
  if not client.enabled(): return # Default runs do not even query telemetry clocks.
  client.tick(getMonoTime().ticks div 1_000_000, eventTimestamp(), peers)

proc startDial*(client: var Client, identity: openArray[byte], target: NetworkEndpoint): EventId =
  ## Copy the actual configured remote tuple before dialing; address data grants no peer authority.
  if not client.enabled() or identity.len != 32 or not target.valid: return EventId(0)
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = identity[i] # No mutable peer storage escapes into the exporter.
  client.dialing(getMonoTime().ticks div 1_000_000, eventTimestamp(), key, target.address.bytes, target.port)

proc startDial*(client: var Client, identity: openArray[byte], port: uint16, ipv6: bool): EventId =
  ## Legacy isolated proof callers retain their explicit loopback observation.
  client.startDial(identity, networkEndpoint(loopbackAddress(ipv6), port))

proc finishDial*(client: var Client, attempt: EventId, authenticated: bool) =
  ## Settle an outgoing attempt exactly once; callers use native authentication evidence, not application success.
  if not client.enabled(): return # Disabled telemetry does not query clocks or encode frames.
  client.dialOutcome(getMonoTime().ticks div 1_000_000, eventTimestamp(), attempt, authenticated)

proc finishConnection*(client: var Client, identity: openArray[byte]) =
  ## Copy the authenticated outgoing identity only after the caller observes a native connection close.
  if not client.enabled() or identity.len != 32: return # Invalid or disabled peers cannot emit a closure.
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = identity[i] # No caller storage is retained by the bounded exporter.
  client.peerDisconnected(getMonoTime().ticks div 1_000_000, eventTimestamp(), key)

type IncomingAttempts* = object ## Fixed correlation storage belongs to the peer and outlives native SSL destruction callbacks.
  active: array[IncomingHandshakeSlots, bool]
  ids: array[IncomingHandshakeSlots, EventId]

proc observeIncoming*(client: var Client, attempts: var IncomingAttempts, slot: cuint,
    event: cint, address: ptr ConstByte, port: uint16, der: ptr ConstByte, length: csize_t) =
  ## Copy callback data immediately; only bounded frames are queued here, never socket operations.
  let stamp = eventTimestamp()
  if event == AdmissionRefused:
    if address == nil:
      client.omit(stamp) # A real refusal without endpoint metadata is a dropped observation.
      return
    var remote = default(array[16, byte])
    let source = cast[ptr UncheckedArray[byte]](address)
    for i in 0..<16: remote[i] = source[i] # The native stack borrow ends with this callback.
    client.refusing(getMonoTime().ticks div 1_000_000, stamp, remote, port)
    return # Refusals neither allocate nor settle handshake correlation slots.
  if event == HandshakeDropped or slot >= cuint(IncomingHandshakeSlots):
    client.omit(stamp) # Overflow or missing primitive metadata cannot fabricate an attempt.
    return
  let index = int(slot)
  let now = getMonoTime().ticks div 1_000_000
  if event == HandshakeStarted:
    if address == nil: # A missing address is not the all-zero endpoint.
      client.omit(stamp)
      return
    var remote = default(array[16, byte])
    let source = cast[ptr UncheckedArray[byte]](address)
    for i in 0..<16: remote[i] = source[i] # Borrow ends before the callback returns.
    attempts.ids[index] = client.accepting(now, stamp, remote, port)
    attempts.active[index] = true
  elif event == HandshakeSucceeded or event == HandshakeFailed:
    if not attempts.active[index]: # A missing start cannot acquire another attempt's ID.
      client.omit(stamp)
      return
    attempts.active[index] = false
    var identity = default(array[32, byte])
    if event == HandshakeSucceeded:
      var fields {.noinit.}: CertFields
      if der == nil or length == 0 or length > 8192 or
          parseCert(cast[ptr byte](der), length, addr fields) != 1 or
          fields.edKey != 1 or fields.keyLength != 32:
        client.omit(stamp) # Authentication succeeded but unusable metadata cannot become a failure.
        return
      for i in 0..<32: identity[i] = fields.key[i] # Native extraction initializes these owned fields.
    client.acceptOutcome(now, stamp, attempts.ids[index], identity, event == HandshakeSucceeded)

# The admitted-peer table copies authenticated public identities; no TLS/native pointer is retained.
type IncomingPeers* = object
  active, known: array[IncomingPeerSlots, bool]
  identities: array[IncomingPeerSlots, array[32, byte]]

proc observePeer*(client: var Client, peers: var IncomingPeers, slot: cuint,
    event: cint, der: ptr ConstByte, length: csize_t) =
  ## Retain the admitted identity for event 27, which requires a close observed while the
  ## transport is alive. Failed handshakes and capacity refusals have no admitted identity.
  ## Clear the slot before emitting so a repeated callback cannot report another closure.
  if slot >= cuint(IncomingPeerSlots): return # Native registration proves this bound; reject invalid callbacks.
  let index = int(slot)
  if event == PeerAccepted:
    peers.active[index] = true
    peers.known[index] = false # Slot reuse never inherits the previous peer's identity.
    peers.identities[index] = default(array[32, byte])
    var fields {.noinit.}: CertFields
    if der == nil or length == 0 or length > 8192 or
        parseCert(cast[ptr byte](der), length, addr fields) != 1 or
        fields.edKey != 1 or fields.keyLength != 32: return # Missing metadata cannot invent a public identity.
    for i in 0..<32: peers.identities[index][i] = fields.key[i] # Copy while native DER remains borrowed.
    peers.known[index] = true
  elif event == PeerClosed and peers.active[index]:
    peers.active[index] = false # Duplicate notifications cannot emit another closure for this lifetime.
    let stamp = eventTimestamp()
    if peers.known[index]:
      client.peerDisconnected(getMonoTime().ticks div 1_000_000, stamp, peers.identities[index])
    else:
      client.omit(stamp) # A real close with unavailable identity is a dropped observation.
    peers.known[index] = false
    peers.identities[index] = default(array[32, byte])
