# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One pinned outgoing ancestor request owns its native endpoint, receiver and callback binding.
## Nonblocking host ticks authenticate, transfer and retire the stream before exposing producer decoding.
import std/assertions
import ../../quic/transport
import ../protocol
import ./stream as ancestor_stream
import ../../app/ancestor/[response as ancestor_response, receiver as ancestor_receiver]
import ../../codec/[bounded, block_codec]

type
  AncestorPeerKey* = distinct array[32, byte] ## Explicit expected TLS Ed25519 identity, unrelated to a header hash.
  AncestorPeerStage* {.pure.} = enum ## Ready requires both FINs and actual final native stream close.
    Idle, Connecting, Receiving, Disconnecting, Ready, Failed
  AncestorPeerError* {.pure.} = enum ## Scalar lifetime failures retain no usable response prefix.
    Uninitialized, None, Busy, InvalidPolicy, InvalidRequest, InvalidEndpoint,
    TransportFailure, IdentityFailure, FramingFailure, Timeout
  AncestorPeer* = object ## Stable exclusive callback owner; callers must close before moving or destroying it.
    transport: Transport
    receiver: AncestorReceiver
    route: AncestorStream
    id: AncestorReceiveId
    handle: NativeStream
    expected: AncestorPeerKey
    limits: AncestorStreamLimits
    started, lastTick: AncestorTick
    state: AncestorPeerStage
    reason: AncestorPeerError
    opened, checked, verified, pending, bound: bool

proc `=copy`*(destination: var AncestorPeer, source: AncestorPeer) {.error:
    "AncestorPeer owns transport and stable callback addresses".}
  ## Composite native owners require their own explicit copy contract.
proc `=dup`*(source: AncestorPeer): AncestorPeer {.error.}
  ## Moving an active peer would invalidate native callback addresses; explicit close precedes owner retirement.
proc `=wasMoved`*(peer: var AncestorPeer) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(peer.transport)
  `=wasMoved`(peer.receiver)
  `=wasMoved`(peer.route)
  `=wasMoved`(peer.id)
  `=wasMoved`(peer.handle)
  `=wasMoved`(peer.expected)
  `=wasMoved`(peer.limits)
  `=wasMoved`(peer.started)
  `=wasMoved`(peer.lastTick)
  `=wasMoved`(peer.state)
  `=wasMoved`(peer.reason)
  `=wasMoved`(peer.opened)
  `=wasMoved`(peer.checked)
  `=wasMoved`(peer.verified)
  `=wasMoved`(peer.pending)
  `=wasMoved`(peer.bound)

proc `=destroy`*(peer: AncestorPeer) =
  ## The caller retires transport callbacks while this aggregate and all nested owners still exist.
  assert not peer.opened and not peer.route.active and peer.handle == NativeStream(nil), "AncestorPeer requires explicit close"
  `=destroy`(peer.transport)
  `=destroy`(peer.receiver)
  `=destroy`(peer.route)
func stage*(peer: AncestorPeer): AncestorPeerStage =
  ## Observe host progress without touching captured raw bytes.
  peer.state
func failure*(peer: AncestorPeer): AncestorPeerError {.requires: peer.state ==
    AncestorPeerStage.Failed.} =
  ## Only terminal failures expose a selected host reason.
  peer.reason
func framingError*(peer: AncestorPeer): AncestorReceiveError {.requires:
    peer.state == AncestorPeerStage.Failed and peer.reason == AncestorPeerError.FramingFailure.} =
  ## A failed native response preserves the original bounded receiver reason.
  peer.receiver.failure

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Compare actual TLS-owned DER against the explicitly selected principal before opening a CE stream.
  let peer = cast[ptr AncestorPeer](user)
  if not peer.opened: return 0 # Teardown never grants new identity authority.
  peer.checked = true
  peer.verified = validPeer(cast[ptr byte](der), length, array[32, byte](peer.expected))
  cint(peer.verified)

proc streamEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Only one locally requested stream can borrow the stable receiver; unsolicited streams are aborted.
  let peer = cast[ptr AncestorPeer](user)
  if event == 0:
    if not peer.opened or not peer.pending or not peer.verified or
        peer.handle != NativeStream(nil) or not peer.transport.locallyOpened(stream):
      streamAbort(stream)
      return # A foreign/late open cannot replace the exact requested callback binding.
    peer.handle = stream
    peer.pending = false
    let result = peer.route.bindStream(peer.receiver, peer.id, stream, peer.limits, peer.lastTick)
    if result != AncestorStreamError.None:
      peer.reason = AncestorPeerError.TransportFailure
      peer.state = AncestorPeerStage.Failed
      streamAbort(stream) # Even refused native bindings retain their handle through final close.
    else:
      peer.bound = true
      peer.state = AncestorPeerStage.Receiving
  elif stream == peer.handle and stream != NativeStream(nil):
    if peer.bound:
      discard peer.route.streamEvent(peer.receiver, peer.id, stream,
          event) # Binding checks exact handle, address and generation.
    if event == 3:
      peer.handle = NativeStream(nil)
      peer.bound = false # Final native close alone ends the receiver borrow.

proc close*(peer: var AncestorPeer) =
  ## Safe after any startup/transfer stage; callback fields remain intact until the engine's final close callbacks return.
  peer.transport.closeTransport()
  assert not peer.route.active and peer.handle == NativeStream(nil)
  if peer.receiver.stage != AncestorReceiveStage.Idle:
    discard peer.receiver.cancel(peer.id) # Callback retirement precedes buffer acknowledgement or reuse.
  peer.opened = false
  peer.pending = false
  peer.bound = false
  peer.state = AncestorPeerStage.Idle
  peer.reason = AncestorPeerError.None

proc open*(peer: var AncestorPeer, request: AncestorRequest, maxBytes: ByteLimit,
    expected: AncestorPeerKey, port: uint16, certificate, key, alpn: string,
    limits: AncestorStreamLimits, now: AncestorTick): AncestorPeerError =
  ## Validate all static input before allocating an endpoint; no background thread or implicit peer discovery exists.
  if peer.opened: return AncestorPeerError.Busy
  if port == 0: return AncestorPeerError.InvalidEndpoint
  if not request.valid: return AncestorPeerError.InvalidRequest
  if uint64(limits.readBytes) == 0 or uint64(limits.readBytes) > 4096 or
      uint64(limits.writeBytes) == 0 or uint64(limits.writeBytes) > 42 or uint64(limits.timeout) == 0 or
      uint64(maxBytes) > uint64(high(uint32)) or uint64(maxBytes) > uint64(high(int)):
    return AncestorPeerError.InvalidPolicy
  let begun = peer.receiver.begin(request, maxBytes)
  if begun.error != AncestorReceiveError.None: return AncestorPeerError.InvalidRequest
  peer.id = begun.value
  peer.expected = expected
  peer.limits = limits
  peer.started = now
  peer.lastTick = now
  peer.checked = false
  peer.verified = false
  peer.pending = false
  peer.bound = false
  peer.reason = AncestorPeerError.None
  peer.state = AncestorPeerStage.Connecting
  peer.opened = true
  let context = cast[pointer](addr peer) # Stable outer owner, never a temporary/copy of a nested field.
  let opened = peer.transport.openTransport(false, false, 0, certificate, key, alpn,
    context, verify, streamEvent)
  if not opened:
    peer.close()
    return AncestorPeerError.TransportFailure # Partial endpoint setup retains no callback borrow.
  if not peer.transport.connectTransport(port):
    peer.close()
    return AncestorPeerError.TransportFailure # A failed dial releases its complete native endpoint and raw buffer.
  AncestorPeerError.None

proc stop(peer: var AncestorPeer, reason: AncestorPeerError): AncestorPeerError =
  ## Join all native callback lifetimes before retaining a terminal host-only reason.
  peer.close()
  peer.state = AncestorPeerStage.Failed
  peer.reason = reason
  reason

proc tick*(peer: var AncestorPeer, now: AncestorTick): AncestorPeerError =
  ## One nonblocking transport turn covers handshake, stream dispatch and actual native retirement.
  if not peer.opened: return AncestorPeerError.Uninitialized
  if peer.state == AncestorPeerStage.Failed: return peer.reason
  if peer.state == AncestorPeerStage.Ready: return AncestorPeerError.None
  if uint64(now) < uint64(peer.lastTick): return AncestorPeerError.InvalidPolicy # Backward ticks cannot underflow a deadline.
  peer.lastTick = now
  if uint64(now) - uint64(peer.started) >= uint64(peer.limits.timeout):
    return peer.stop(AncestorPeerError.Timeout) # One total deadline includes TLS and final callback retirement.
  let polled = peer.transport.pollTransport(0)
  if peer.checked and not peer.verified: return peer.stop(AncestorPeerError.IdentityFailure)
  if not polled: return peer.stop(AncestorPeerError.TransportFailure)
  if peer.state == AncestorPeerStage.Failed: return peer.reason
  if peer.state == AncestorPeerStage.Connecting and peer.verified and
      peer.transport.authenticatedConnections > 0:
    peer.pending = true
    peer.state = AncestorPeerStage.Receiving
    peer.transport.openStream() # Exactly one locally requested stream follows actual pinned authentication.
  if peer.receiver.stage == AncestorReceiveStage.Failed:
    peer.state = AncestorPeerStage.Failed
    peer.reason = AncestorPeerError.FramingFailure
    return peer.reason # Retain the exact framing reason until explicit close retires all native callbacks.
  if peer.receiver.stage == AncestorReceiveStage.Idle:
    return peer.stop(AncestorPeerError.TransportFailure) # Reset/unclean close cannot manufacture an empty response.
  if peer.receiver.stage == AncestorReceiveStage.Ready and not peer.route.active and peer.handle ==
      NativeStream(nil):
    if peer.state != AncestorPeerStage.Disconnecting:
      peer.transport.disconnectTransport()
      peer.state = AncestorPeerStage.Disconnecting # Send graceful connection close before a later owner reuses this single-peer server.
    elif peer.transport.peerMetric(0) == 0:
      peer.state = AncestorPeerStage.Ready # Native connection retirement follows stream FIN/close and close-packet processing.
  AncestorPeerError.None

proc response*(peer: AncestorPeer, frame: FrameConfig,
    headerBytes: ByteLimit): AncestorResponseResult[AncestorResponse] {.requires:
    peer.state == AncestorPeerStage.Ready.} =
  ## Decode only from the host after successful native retirement; no canonical state is retained or modified.
  peer.receiver.response(peer.id, frame, headerBytes)
