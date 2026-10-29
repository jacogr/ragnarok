# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS ancestor-stream client reuses the independent finite responder and native transport policy.
import std/[assertions, envvars]
import ../../src/codec/bounded
import ../../src/app/ancestor_receiver
import ../../src/quic/[transport, protocol, ancestor_stream]
import ./block_download_transport

type AncestorClient = object ## Stable exclusive callback owner outlives every native stream close event.
  transport: Transport
  download: nil ptr AncestorReceiver
  id: AncestorReceiveId
  stream: NativeStream
  route: AncestorStream
  reset, fragmented: bool
proc `=copy`(destination: var AncestorClient, source: AncestorClient) {.error.}
  ## A transport and callback binding cannot be duplicated.
proc `=dup`(source: AncestorClient): AncestorClient {.error.}
  ## Callback addresses remain stable through transport teardown.
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Apply the unchanged JAM TLS certificate policy; explicit peer pinning belongs to the next owner layer.
  cint(validPeer(cast[ptr byte](der), length, []))

proc clientEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Perform at most one small native read/write per callback; preparation never occurs here.
  let client = cast[ptr AncestorClient](user)
  let borrowed = client.download
  if borrowed == nil:
    assert false, "missing stable producer borrow"
    return # Native callbacks must never outlive or precede producer binding.
  let receiver = borrowed # The nil guard remains valid across successive mutable pointee calls.
  if event == 0:
    assert client.stream == NativeStream(nil)
    client.stream = stream
    var limits = AncestorStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: AncestorTimeout(100))
    assert client.route.bindStream(receiver[], client.id, NativeStream(nil), limits,
      AncestorTick(100)) == AncestorStreamError.InvalidStream
    limits.readBytes = ByteLimit(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.InvalidPolicy
    limits.readBytes = ByteLimit(4097)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.InvalidPolicy
    limits.readBytes = ByteLimit(73)
    limits.writeBytes = ByteLimit(43)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.InvalidPolicy
    limits.writeBytes = ByteLimit(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.InvalidPolicy
    limits.writeBytes = ByteLimit(3)
    limits.timeout = AncestorTimeout(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.InvalidPolicy
    limits.timeout = AncestorTimeout(100)
    var absent = default(AncestorReceiver)
    assert client.route.bindStream(absent, client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.NotReceiving
    assert client.route.bindStream(receiver[], AncestorReceiveId(0), stream, limits,
      AncestorTick(100)) == AncestorStreamError.StaleReceiver
    if client.fragmented:
      limits.readBytes = ByteLimit(1)
      limits.writeBytes = ByteLimit(1) # Force individual E4 header bytes and every request offset through native callbacks.
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.None
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      AncestorTick(100)) == AncestorStreamError.Busy
    assert not client.route.expire(receiver[], client.id, stream, AncestorTick(99))
    assert not client.route.expire(receiver[], client.id, stream, AncestorTick(199))
  else:
    # Native callbacks retain the exact mapping installed at open; synthetic foreign events are inert.
    var foreign = default(AncestorReceiver)
    assert not client.route.streamEvent(foreign, client.id, stream, 3)
    assert not client.route.streamEvent(receiver[], AncestorReceiveId(0), stream, 3)
    assert not client.route.streamEvent(receiver[], client.id, NativeStream(nil), 3)
    assert not client.route.cancel(foreign, client.id, stream)
    assert not client.route.expire(foreign, client.id, stream, AncestorTick(high(uint64)))
    assert not client.route.streamEvent(receiver[], client.id, stream, 99)
    assert client.route.streamEvent(receiver[], client.id, stream, event)
    if event == 3:
      client.stream = NativeStream(nil)
      assert not client.route.active
      assert not client.route.streamEvent(receiver[], client.id, stream, 1)
      assert not client.route.streamEvent(receiver[], client.id, stream, 2)
      assert not client.route.streamEvent(receiver[], client.id, stream, 3)
    elif event == 4:
      client.reset = true # The callback is recorded independently of explicit cancellation tests.

proc exchangeAncestors*(receiver: var AncestorReceiver, id: AncestorReceiveId,
    expected: array[42, byte], response: seq[byte], mode: DownloadTransferMode,
    fragmented = false) =
  ## Actual responder checks all request bytes/FIN independently; transport close retires callbacks before returning.
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected, response, mode)
  defer: servers.close()
  var client = default(AncestorClient)
  client.download = addr receiver
  client.id = id
  client.fragmented = fragmented
  defer:
    client.transport.closeTransport() # Receiver, route and callback owner remain alive through final close.
    assert not client.route.active and client.stream == NativeStream(nil)
  assert client.transport.openTransport(false, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr client, verify, clientEvent)
  assert client.transport.connectTransport(servers.port(false))
  var opened = false
  var settled = false
  for attempt in 0..<2000:
    assert servers.poll() and client.transport.pollTransport(1)
    if not opened and client.transport.authenticatedConnections > 0:
      client.transport.openStream()
      opened = true # No application request precedes actual TLS authentication.
    if mode in [NoFin, Deadline, ResetEvent] and client.route.receivedBytes == uint64(response.len):
      assert receiver.stage == AncestorReceiveStage.Receiving
      if mode == Deadline:
        assert client.route.expire(receiver, id, client.stream, AncestorTick(200))
        assert not client.route.expire(receiver, id, client.stream, AncestorTick(high(uint64)))
      elif mode == ResetEvent:
        assert client.route.streamEvent(receiver, id, client.stream, 4)
        assert client.route.streamEvent(receiver, id, client.stream, 4)
      else:
        assert client.route.cancel(receiver, id, client.stream) # Cancelling complete bytes cannot manufacture response FIN.
      assert receiver.stage == AncestorReceiveStage.Idle and client.route.active
      assert client.route.streamEvent(receiver, id, client.stream, 1)
      assert client.route.streamEvent(receiver, id, client.stream, 2)
      assert client.route.receivedBytes == uint64(response.len)
      settled = true
      break
    if receiver.stage in [AncestorReceiveStage.Ready, AncestorReceiveStage.Failed] or client.reset:
      settled = true
      break # A completed handshake or request alone is never a successful response.
  assert opened and settled and servers.requestCount(false) == 1, "ancestor transfer " & $mode
  if mode in [Healthy, EmptyReply]:
    assert receiver.stage == AncestorReceiveStage.Ready # Both actual FINs precede producer decoding after return.
  elif mode == Oversized:
    assert receiver.stage == AncestorReceiveStage.Failed
    assert receiver.failure == AncestorReceiveError.LimitExceeded
  elif mode == PrematureClose:
    assert receiver.stage == AncestorReceiveStage.Failed
    assert receiver.failure == AncestorReceiveError.Truncated
  else:
    assert receiver.stage == AncestorReceiveStage.Idle # Explicit abort/deadline leaves no captured bytes.
