# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent one-stream LSQUIC responder exercises real CE 128 bytes/FIN and close/cancellation lifetimes.

import std/[assertions, envvars]
import ../../src/app/block_download
import ../../src/quic/[transport, protocol]

type
  DownloadTransferMode* = enum ## Each fixture mode changes only server wire/lifecycle behavior.
    Healthy, Oversized, PrematureClose, NoFin
  DownloadClient = object ## Stable callback owner borrows the producer until both engines finish native teardown.
    transport: Transport
    download: nil ptr BlockDownload
    id: BlockDownloadId
    stream: NativeStream
    request: array[42, byte]
    offset, received: int
    reset, writeFin: bool
  DownloadServer = object ## One independent responder retains expected request and actual write offsets through close.
    transport: Transport
    stream: NativeStream
    expected, request: array[42, byte]
    response: seq[byte]
    received, offset: int
    mode: DownloadTransferMode
    requestFin, writeFin, reset: bool

proc `=copy`(destination: var DownloadClient, source: DownloadClient) {.error: "Test client owns transport".}
  ## Callback addresses stay stable while native streams borrow this owner.
proc `=copy`(destination: var DownloadServer, source: DownloadServer) {.error: "Test server owns transport".}
  ## The responder's descriptor/engine cannot be duplicated.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Apply the real pinned certificate identity policy to the freshly generated local fixture.
  cint(validPeer(cast[ptr byte](der), length, []))

proc clientEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Perform at most one small native read/write per callback; preparation never occurs here.
  let client = cast[ptr DownloadClient](user)
  let receiver = client.download
  if receiver == nil:
    assert false, "missing stable producer borrow"
    return # Native callbacks must never outlive or precede producer binding.
  case event
  of 0:
    assert client.stream == NativeStream(nil)
    client.stream = stream
    wantRead(stream, 1)
    wantWrite(stream, 1)
  of 1:
    var buffer = default(array[73, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return # Native would-block retains the same callback/input generation.
    if count < 0:
      client.reset = true
      discard receiver[].cancel(client.id)
      streamAbort(stream)
      return # A reset has no implicit FIN or usable application prefix.
    if count == 0:
      readDone(stream)
      wantRead(stream, 0)
      discard receiver[].append(client.id, [], true) # Only actual EOF supplies response FIN.
    else:
      assert count <= int64(buffer.len)
      client.received += int(count)
      let received = receiver[].append(client.id, buffer.toOpenArray(0, int(count) - 1), false)
      if received != BlockDownloadError.None: streamAbort(
          stream) # Framing failure aborts only this native stream.
  of 2:
    if client.offset < client.request.len:
      let count = streamWrite(stream, addr client.request[client.offset], csize_t(min(3,
          client.request.len - client.offset)))
      if count == -2: return # The next write callback resumes the exact retained offset.
      assert count >= 0 and count <= int64(client.request.len - client.offset)
      client.offset += int(count)
    if client.offset == client.request.len and not client.writeFin:
      client.writeFin = true
      wantWrite(stream, 0)
      streamFin(stream)
      assert receiver[].requestFinished(client.id) == BlockDownloadError.None
  of 3:
    client.stream = NativeStream(nil)
    if receiver[].stage == BlockDownloadStage.Receiving:
      discard receiver[].cancel(client.id) # Premature close cannot authorize candidate preparation.
  of 4:
    client.reset = true
    if receiver[].stage == BlockDownloadStage.Receiving:
      discard receiver[].cancel(client.id) # Keep an already selected framing failure observable for acknowledgement.
  else:
    assert false, "undefined native client event" # Bridge ABI changes must fail the fixture.

proc serverEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Independently validate all 42 request bytes and actual request FIN before writing a fixture response.
  let server = cast[ptr DownloadServer](user)
  case event
  of 0:
    assert server.stream == NativeStream(nil)
    server.stream = stream
    wantRead(stream, 1)
  of 1:
    var buffer = default(array[64, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return # No framing decision is made on incomplete transport input.
    if count < 0: server.reset = true; return # Peer cancellation never becomes a successful request.
    if count == 0:
      assert server.received == 42 and server.request == server.expected
      server.requestFin = true
      readDone(stream)
      wantRead(stream, 0)
      if server.mode == PrematureClose:
        streamAbort(stream) # Closing without an E4 message is a truncated response, not a valid empty sequence.
      else:
        wantWrite(stream, 1) # Response emission follows the complete request and its clean half-close.
    else:
      assert count <= int64(42 - server.received)
      for index in 0..<int(count): server.request[server.received + index] = buffer[
          index] # Bound the independent fixed request buffer.
      server.received += int(count)
  of 2:
    if server.reset: return # No response resumes after native cancellation.
    if server.offset < server.response.len:
      let count = streamWrite(stream, addr server.response[server.offset], csize_t(min(7,
          server.response.len - server.offset)))
      if count == -2: return # Native flow control retains the original serialized response bytes.
      assert count >= 0 and count <= int64(server.response.len - server.offset)
      server.offset += int(count)
    if server.offset == server.response.len and not server.writeFin:
      wantWrite(stream, 0)
      server.writeFin = true
      if server.mode == NoFin:
        discard streamFlush(stream) # Exact body bytes deliberately do not terminate this direction.
      else:
        streamFin(stream) # Normal framing/oversized header modes still terminate their actual wire.
  of 3:
    server.stream = NativeStream(nil) # Last callback ends all native borrows before stack teardown.
  of 4:
    server.reset = true # Directional reset retires application writes without fabricating FIN.
  else:
    assert false, "undefined native server event" # Undefined ABI events are never silently accepted.

proc exchangeBlock*(download: var BlockDownload, id: BlockDownloadId,
    expected: array[42, byte], response: seq[byte], mode: DownloadTransferMode) =
  ## Establish real authenticated UDP/QUIC streams, then retire callbacks before returning to producer work.
  var server = default(DownloadServer)
  var client = default(DownloadClient)
  client.download = addr download
  client.id = id
  client.request = download.request(id).value
  server.expected = expected
  server.mode = mode
  server.response = if mode == Oversized: @[255'u8, 255, 255, 255] else: response
  defer:
    client.transport.closeTransport() # The borrowed download and both callback owners remain live through final close.
    server.transport.closeTransport()
  let cert = getEnv("RAGNAROK_TEST_CERT")
  let key = getEnv("RAGNAROK_TEST_KEY")
  assert server.transport.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
      addr server, verify, serverEvent)
  assert client.transport.openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000",
      addr client, verify, clientEvent)
  assert client.transport.connectTransport(server.transport.localPort)
  var opened = false
  var settled = false
  for attempt in 0..<2000:
    assert server.transport.pollTransport(1) and client.transport.pollTransport(1)
    if not opened and client.transport.authenticatedConnections > 0:
      client.transport.openStream()
      opened = true # Open one actual CE stream only after authenticated transport admission.
    if mode == NoFin and client.received == response.len:
      assert download.stage == BlockDownloadStage.Receiving
      assert download.cancel(id)
      if client.stream != NativeStream(nil): streamAbort(
          client.stream) # Explicit cancellation retires a complete-but-unfinished body.
      settled = true
      break
    if download.stage in [BlockDownloadStage.Ready, BlockDownloadStage.Failed] or client.reset:
      settled = true
      break # Return only an observed actual response/reset outcome, never merely a successful handshake.
  assert opened and settled and server.requestFin, "mode " & $mode & " opened=" & $opened &
      " settled=" & $settled & " requestFin=" & $server.requestFin & " stage=" & $download.stage
  if mode == Healthy:
    assert download.stage == BlockDownloadStage.Ready, "healthy stage " &
        $download.stage # Only both clean FIN observations authorize producer work.
  elif mode == Oversized:
    assert download.stage == BlockDownloadStage.Failed, "oversized stage " & $download.stage
    assert download.failure.error == BlockDownloadError.LimitExceeded
  elif mode == PrematureClose:
    assert download.stage == BlockDownloadStage.Failed
    assert download.failure.error == BlockDownloadError.Truncated
  else:
    assert download.stage == BlockDownloadStage.Idle, "cancelled stage " &
        $download.stage # Explicit no-FIN cancellation retires partial reception.
