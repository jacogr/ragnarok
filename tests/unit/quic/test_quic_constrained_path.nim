# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete mutual TLS and a multi-packet request/reply through the real QUIC
## transport. Linux applies the minimum IPv6 MTU without changing host routes.
## A single dropped packet and one reversed pair exercise QUIC recovery on the
## same path, with exact application bytes and FIN as the success criterion.

import std/[assertions, envvars, syncio, monotimes, times]
include ../../../src/quic/transport

const
  ReplySize = 16 * 1024
  RequestByte = 42'u8

type
  Exchange = object ## Each endpoint retains its own stream progress and bounded application buffers.
    server, readFin, writeFin: bool
    written, received: int
    request: array[1, byte]
    reply: array[ReplySize, byte]
    dropped, reordered: bool
    heldLength: int
    held: array[2048, byte]

func replyByte(offset: int): byte =
  ## A varying pattern detects omitted, duplicated and misplaced response ranges.
  byte((offset * 29 + offset div 127) mod 251)

proc acceptFixture(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl.} =
  ## This transport test uses generated Ed25519 fixtures. JAM identity checks have their own suite.
  if length > 0: 1.cint else: 0.cint

proc exchangeStream(user: pointer, handle: NativeStream, event: cint) {.cdecl.} =
  ## Send one request and FIN, then require all response bytes and an independent peer FIN.
  let flow = cast[ptr Exchange](user)
  case event
  of 0:
    wantRead(handle, 1)
    if not flow.server: wantWrite(handle, 1) # The client sends the first message.
  of 1:
    var chunk = default(array[2048, byte])
    let count = streamRead(handle, addr chunk[0], csize_t(chunk.len))
    if count == -2: return # No application byte or FIN is readable yet.
    assert count >= 0 and count <= int64(chunk.len), "stream read failed"
    if count == 0:
      assert flow.received == (if flow.server: 1 else: ReplySize), "premature FIN"
      flow.readFin = true
      readDone(handle)
      wantRead(handle, 0)
      if flow.server: wantWrite(handle, 1) # The response starts after the complete request.
      return
    if flow.server:
      assert flow.received == 0 and count == 1 and chunk[0] == RequestByte
    else:
      assert int(count) <= ReplySize - flow.received
      for index in 0..<int(count):
        assert chunk[index] == replyByte(flow.received + index)
    flow.received += int(count)
  of 2:
    if flow.writeFin: return # An already queued notification cannot duplicate FIN.
    let remaining = (if flow.server: ReplySize else: 1) - flow.written
    let data = if flow.server: addr flow.reply[flow.written] else: addr flow.request[0]
    let count = streamWrite(handle, data, csize_t(remaining))
    if count in [-2'i64, 0]: return # Native backpressure leaves existing progress intact.
    assert count > 0 and count <= int64(remaining), "stream write failed"
    flow.written += int(count)
    if count == int64(remaining):
      flow.writeFin = true
      wantWrite(handle, 0)
      streamFin(handle)
  of 3:
    discard # The test owner outlives every close callback.
  of 4:
    assert false, "unexpected stream reset"
  else:
    discard # No other native event supplies application bytes.

proc constrainedSend(user: pointer, bytes: ptr ConstByte, length: csize_t,
    address: ptr ConstByte, port: uint16): cint {.cdecl, raises: [].} =
  ## Drop the first large response datagram, then deliver the next two in reverse order.
  ## Small ACKs and all handshake datagrams go directly through the production socket.
  let owner = cast[ptr Transport](user)
  let flow = cast[ptr Exchange](owner.user)
  if not flow.readFin or flow.reordered or length < 1000:
    return sendPacket(user, bytes, length, address, port)
  if not flow.dropped:
    flow.dropped = true
    return 0 # Model loss after a successful send so QUIC drives retransmission.
  if flow.heldLength == 0:
    assert length <= csize_t(flow.held.len)
    let packet = cast[ptr UncheckedArray[byte]](bytes)
    for index in 0..<int(length): flow.held[index] = packet[index]
    flow.heldLength = int(length)
    return 0 # Copy once because the writer's input expires when this callback returns.
  let error = sendPacket(user, bytes, length, address, port)
  if error != 0: return error # QUICHE can retry without delivering the retained packet first.
  let delayed = cast[ptr ConstByte](addr flow.held[0])
  assert sendPacket(user, delayed, csize_t(flow.heldLength), address, port) == 0
  flow.reordered = true
  0

when defined(linux):
  let
    Ipv6Level {.importc: "IPPROTO_IPV6", header: "<netinet/in.h>".}: cint
    Ipv6Mtu {.importc: "IPV6_MTU", header: "<netinet/in.h>".}: cint
    Ipv6DontFrag {.importc: "IPV6_DONTFRAG", header: "<netinet/in.h>".}: cint

  proc setPathOption(fd, level, option: cint, value: ptr cint,
      length: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
    ## Apply Linux's per-socket minimum path size without changing loopback or needing privileges.

  proc constrain(sender, receiver: Transport) =
    ## Prove the kernel rejects a 1281-byte IPv6 packet and carries a 1280-byte packet intact.
    const MaxPayload = 1280 - 40 - 8
    let fd = sender.socket.descriptor
    var value = 1280.cint
    assert setPathOption(fd, Ipv6Level, Ipv6Mtu, addr value, SockLen(sizeof(value))) == 0
    value = 1
    assert setPathOption(fd, Ipv6Level, Ipv6DontFrag, addr value, SockLen(sizeof(value))) == 0
    let target = networkEndpoint(loopbackAddress(true), receiver.localPort)
    var probe = default(array[MaxPayload + 1, byte])
    probe[0] = 123
    assert sender.socket.sendError(addr probe[0], probe.len, target) == EMSGSIZE,
      "1281 bytes must exceed the actual socket path MTU"
    assert sender.socket.sendError(addr probe[0], MaxPayload, target) == 0
    var observed = default(array[MaxPayload + 1, byte])
    var source = default(NetworkEndpoint)
    assert receiver.socket.receive(observed, source) == MaxPayload and observed == probe
    assert source == networkEndpoint(loopbackAddress(true), sender.localPort)

proc main() {.raises.} =
  ## Drive the real selector and QUIC timers until both application halves finish.
  let args = [getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")]
  assert args[0].len > 0 and args[1].len > 0
  const Alpn = "jamnp-s/1/00000000"
  var incoming = Exchange(server: true)
  var outgoing = Exchange(request: [RequestByte])
  for index in 0..<incoming.reply.len: incoming.reply[index] = replyByte(index)
  var server = default(Transport)
  var client = default(Transport)
  defer:
    client.closeTransport()
    server.closeTransport()
  # Inject packet handling through the native writer callback; all reads and writes still use UDP.
  assert server.socket.open(true, 0)
  let dispatcher = newDispatcher()
  server.selector = dispatcher
  server.selectorOwned = true
  assert dispatcher.register(server.socket)
  server.registered = true
  server.ipv6 = true
  server.peerCapacity = IncomingPeerSlots
  server.user = addr incoming
  server.verify = acceptFixture
  server.stream = exchangeStream
  var cert = args[0]
  var key = args[1]
  var alpn = Alpn
  var options = NativeTransportOptions(profile: cint(RetainedPeer), server: 1, ipv6: 1)
  server.engine = transportNew(addr options, server.localPort, cert.toCString(), key.toCString(),
    alpn.toCString(), addr server, verifyForward, constrainedSend, streamForward)
  assert server.engine != nil
  assert client.openTransport(false, false, 0, args[0], args[1], Alpn,
    addr outgoing, acceptFixture, exchangeStream, ipv6 = true)
  when defined(linux):
    constrain(client, server)
    constrain(server, client)
  assert client.connectTransport(server.localPort)
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while client.authenticatedConnections == 0 or server.authenticatedConnections == 0:
    assert getMonoTime() < deadline, "mutual TLS did not complete"
    assert client.pollTransport(1) and server.pollTransport(1)
  client.openStream()
  while not outgoing.readFin:
    assert getMonoTime() < deadline, "response did not recover from loss and reordering"
    assert client.pollTransport(1) and server.pollTransport(1)
  assert incoming.readFin and incoming.writeFin and outgoing.writeFin
  assert incoming.dropped and incoming.reordered and outgoing.received == ReplySize
  echo "QUIC constrained path recovered the exact response and FIN"

# Setup failures must exit before the harness can see a successful transcript.
try:
  main()
except:
  quit(2)
