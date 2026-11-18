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
  Loss = object ## At most one delayed datagram is owned between relay turns.
    dropped, reordered: bool
    heldLength: int
    held: array[2048, byte]
  Relay = object ## Each endpoint sees a stable source port on real IPv6 loopback.
    front, back: UdpEndpoint
    loss: Loss

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

proc forward(input, output: UdpEndpoint, source, target: NetworkEndpoint,
    loss: nil ptr Loss) =
  ## Forward complete real UDP datagrams. Drop and delay only large response datagrams.
  var packet = default(array[2048, byte])
  for turn in 0..<MaxReadyBatch:
    var origin = default(NetworkEndpoint)
    let count = input.receive(packet, origin)
    if count == -2: break # Each empty queue yields to the other direction and the protocol timers.
    assert count > 0 and origin == source, "unexpected datagram in the private relay"
    if loss == nil or loss.reordered or count < 1000:
      assert output.sendError(addr packet[0], count, target) == 0
    elif not loss.dropped:
      loss.dropped = true # The production sender already handed its packet to the kernel.
    elif loss.heldLength == 0:
      loss.held = packet # Retain one whole datagram independently of the next receive.
      loss.heldLength = count
    else:
      assert output.sendError(addr packet[0], count, target) == 0
      assert output.sendError(addr loss.held[0], loss.heldLength, target) == 0
      loss.reordered = true

proc pollPath(client, server: var Transport, relay: var Relay, disruptReply: bool) =
  ## Drive the ordinary client and listener, then deliver their datagrams in each direction.
  assert client.pollTransport(1) and server.pollTransport(1)
  let clientAddress = networkEndpoint(loopbackAddress(true), client.localPort)
  let serverAddress = networkEndpoint(loopbackAddress(true), server.localPort)
  relay.front.forward(relay.back, clientAddress, serverAddress, nil)
  let loss = if disruptReply: addr relay.loss else: nil
  relay.back.forward(relay.front, serverAddress, clientAddress, loss)

when defined(linux):
  let
    Ipv6Level {.importc: "IPPROTO_IPV6", header: "<netinet/in.h>".}: cint
    Ipv6Mtu {.importc: "IPV6_MTU", header: "<netinet/in.h>".}: cint
    Ipv6DontFrag {.importc: "IPV6_DONTFRAG", header: "<netinet/in.h>".}: cint

  proc setPathOption(fd, level, option: cint, value: ptr cint,
      length: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
    ## Apply Linux's per-socket minimum path size without changing loopback or needing privileges.

  proc constrain(sender, receiver: UdpEndpoint) =
    ## Prove the kernel rejects a 1281-byte IPv6 packet and carries a 1280-byte packet intact.
    const MaxPayload = 1280 - 40 - 8
    let fd = sender.descriptor
    var value = 1280.cint
    assert setPathOption(fd, Ipv6Level, Ipv6Mtu, addr value, SockLen(sizeof(value))) == 0
    value = 1
    assert setPathOption(fd, Ipv6Level, Ipv6DontFrag, addr value, SockLen(sizeof(value))) == 0
    let target = networkEndpoint(loopbackAddress(true), receiver.port)
    var probe = default(array[MaxPayload + 1, byte])
    probe[0] = 123
    assert sender.sendError(addr probe[0], probe.len, target) == EMSGSIZE,
      "1281 bytes must exceed the actual socket path MTU"
    assert sender.sendError(addr probe[0], MaxPayload, target) == 0
    var observed = default(array[MaxPayload + 1, byte])
    var source = default(NetworkEndpoint)
    assert receiver.receive(observed, source) == MaxPayload and observed == probe
    assert source == networkEndpoint(loopbackAddress(true), sender.port)

proc main() {.raises.} =
  ## Drive the real selector and QUIC timers until both application halves finish.
  let args = [getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")]
  assert args[0].len > 0 and args[1].len > 0
  const Alpn = "jamnp-s/1/00000000"
  var incoming = Exchange(server: true)
  var outgoing = Exchange(request: [RequestByte])
  for index in 0..<incoming.reply.len: incoming.reply[index] = replyByte(index)
  var server, client = default(Transport)
  var relay = default(Relay)
  defer:
    client.closeTransport()
    server.closeTransport()
    relay.front.close()
    relay.back.close()
  assert relay.front.open(true, 0) and relay.back.open(true, 0)
  assert server.openTransport(true, false, 0, args[0], args[1], Alpn,
    addr incoming, acceptFixture, exchangeStream, ipv6 = true)
  assert client.openTransport(false, false, 0, args[0], args[1], Alpn,
    addr outgoing, acceptFixture, exchangeStream, ipv6 = true)
  when defined(linux):
    constrain(client.socket, relay.front)
    constrain(server.socket, relay.back)
  assert client.connectTransport(relay.front.port)
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while client.authenticatedConnections == 0 or server.authenticatedConnections == 0:
    assert getMonoTime() < deadline, "mutual TLS did not complete"
    client.pollPath(server, relay, incoming.readFin)
  client.openStream()
  while not outgoing.readFin:
    assert getMonoTime() < deadline, "response did not recover from loss and reordering"
    client.pollPath(server, relay, incoming.readFin)
  assert incoming.readFin and incoming.writeFin and outgoing.writeFin
  assert relay.loss.dropped and relay.loss.reordered and outgoing.received == ReplySize
  echo "QUIC constrained path recovered the exact response and FIN"

# Setup failures must exit before the harness can see a successful transcript.
try:
  main()
except:
  quit(2)
