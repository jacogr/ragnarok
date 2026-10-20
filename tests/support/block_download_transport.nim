# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent one-stream LSQUIC responder exercises real CE 128 bytes/FIN and close/cancellation lifetimes.

import std/[assertions, envvars]
import ../../src/codec/bounded
import ../../src/app/[block_download, download_schedule, services]
import ../../src/state/accumulation_completion
import ../../src/quic/[transport, protocol, block_download_stream, block_download_session]

type
  DownloadTransferMode* = enum ## Each fixture mode changes only server wire/lifecycle behavior.
    Healthy, EmptyReply, Oversized, PrematureClose, NoFin, Deadline, ResetEvent
  DownloadClient = object ## Stable callback owner borrows the producer until both engines finish native teardown.
    transport: Transport
    download: nil ptr BlockDownload
    id: BlockDownloadId
    stream: NativeStream
    route: BlockDownloadStream
    reset, fragmented: bool
  DownloadServer = object ## One independent responder retains expected request and actual write offsets through close.
    transport: Transport
    stream: NativeStream
    expected, request: array[42, byte]
    response: seq[byte]
    received, offset, requests: int
    mode: DownloadTransferMode
    requestFin, writeFin, reset, allowCancelled: bool

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
  let borrowed = client.download
  if borrowed == nil:
    assert false, "missing stable producer borrow"
    return # Native callbacks must never outlive or precede producer binding.
  let receiver: ptr BlockDownload = borrowed # Preserve a checked non-null borrow across successive mutable receiver calls.
  if event == 0:
    assert client.stream == NativeStream(nil)
    client.stream = stream
    var limits = DownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: DownloadTimeout(100))
    assert client.route.bindStream(receiver[], client.id, NativeStream(nil), limits,
      DownloadTick(100)) == DownloadStreamError.InvalidStream
    limits.readBytes = ByteLimit(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.InvalidPolicy
    limits.readBytes = ByteLimit(4097)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.InvalidPolicy
    limits.readBytes = ByteLimit(73)
    limits.writeBytes = ByteLimit(43)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.InvalidPolicy
    limits.writeBytes = ByteLimit(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.InvalidPolicy
    limits.writeBytes = ByteLimit(3)
    limits.timeout = DownloadTimeout(0)
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.InvalidPolicy
    limits.timeout = DownloadTimeout(100)
    var absent = default(BlockDownload)
    assert client.route.bindStream(absent, client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.NotReceiving
    assert client.route.bindStream(receiver[], BlockDownloadId(0), stream, limits,
      DownloadTick(100)) == DownloadStreamError.StaleDownload
    if client.fragmented:
      limits.readBytes = ByteLimit(1)
      limits.writeBytes = ByteLimit(1) # Force individual E4 header bytes and every request offset through native callbacks.
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.None
    assert client.route.bindStream(receiver[], client.id, stream, limits,
      DownloadTick(100)) == DownloadStreamError.Busy
    assert not client.route.expire(receiver[], client.id, stream, DownloadTick(99))
    assert not client.route.expire(receiver[], client.id, stream, DownloadTick(199))
  else:
    # Native callbacks retain the exact mapping installed at open; synthetic foreign events are inert.
    var foreign = default(BlockDownload)
    assert not client.route.streamEvent(foreign, client.id, stream, 3)
    assert not client.route.streamEvent(receiver[], BlockDownloadId(0), stream, 3)
    assert not client.route.streamEvent(receiver[], client.id, NativeStream(nil), 3)
    assert not client.route.cancel(foreign, client.id, stream)
    assert not client.route.expire(foreign, client.id, stream, DownloadTick(high(uint64)))
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

proc serverEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Independently validate all 42 request bytes and actual request FIN before writing a fixture response.
  let server = cast[ptr DownloadServer](user)
  case event
  of 0:
    assert server.stream == NativeStream(nil)
    server.received = 0
    server.offset = 0
    server.requestFin = false
    server.writeFin = false
    server.reset = false
    server.request = default(array[42, byte]) # Serial catalog retries reuse a responder only after prior native close.
    server.stream = stream
    wantRead(stream, 1)
  of 1:
    var buffer = default(array[64, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return # No framing decision is made on incomplete transport input.
    if count < 0: server.reset = true; return # Peer cancellation never becomes a successful request.
    if count == 0:
      if server.allowCancelled and server.received != 42:
        server.reset = true
        readDone(stream)
        wantRead(stream, 0)
        streamAbort(stream)
        return # Catalog retry fixtures explicitly admit an aborted request before successful binding.
      assert server.received == 42 and server.request == server.expected
      server.requestFin = true
      inc server.requests # Observe completed independent requests per authenticated server identity.
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
      if server.mode in [NoFin, Deadline, ResetEvent]:
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
  client.fragmented = mode == EmptyReply
  server.expected = expected
  server.mode = mode
  server.response = if mode == Oversized: @[255'u8, 255, 255, 255]
    elif mode == EmptyReply: @[0'u8, 0, 0, 0]
    else: response # Every response remains independent of the production controller.
  defer:
    client.transport.closeTransport() # The borrowed download and both callback owners remain live through final close.
    assert not client.route.active and client.stream == NativeStream(nil)
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
    if mode in [NoFin, Deadline, ResetEvent] and client.route.receivedBytes == uint64(response.len):
      assert download.stage == BlockDownloadStage.Receiving
      if mode == Deadline:
        assert client.route.expire(download, id, client.stream, DownloadTick(200))
        assert not client.route.expire(download, id, client.stream, DownloadTick(high(uint64)))
      elif mode == ResetEvent:
        assert client.route.streamEvent(download, id, client.stream, 4)
        assert client.route.streamEvent(download, id, client.stream, 4)
      else:
        assert client.route.cancel(download, id, client.stream) # Explicit cancellation has no implicit FIN.
      assert download.stage == BlockDownloadStage.Idle and client.route.active
      assert client.route.streamEvent(download, id, client.stream, 1)
      assert client.route.streamEvent(download, id, client.stream, 2)
      assert client.route.receivedBytes == uint64(
          response.len) # Stopping callbacks perform no further native I/O.
      let limits = DownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
        timeout: DownloadTimeout(100))
      assert client.route.bindStream(download, id, client.stream, limits,
        DownloadTick(200)) == DownloadStreamError.Busy
      settled = true
      break
    if download.stage in [BlockDownloadStage.Ready, BlockDownloadStage.Empty,
        BlockDownloadStage.Failed] or client.reset:
      settled = true
      break # Return only an observed actual response/reset outcome, never merely a successful handshake.
  assert opened and settled and server.requestFin, "mode " & $mode & " opened=" & $opened &
      " settled=" & $settled & " requestFin=" & $server.requestFin & " stage=" & $download.stage
  if mode == Healthy:
    assert download.stage == BlockDownloadStage.Ready, "healthy stage " &
        $download.stage # Only both clean FIN observations authorize producer work.
  elif mode == EmptyReply:
    assert download.stage == BlockDownloadStage.Empty # E4(0) plus real FIN carries a valid empty block sequence.
  elif mode == Oversized:
    assert download.stage == BlockDownloadStage.Failed, "oversized stage " & $download.stage
    assert download.failure.error == BlockDownloadError.LimitExceeded
  elif mode == PrematureClose:
    assert download.stage == BlockDownloadStage.Failed
    assert download.failure.error == BlockDownloadError.Truncated
  else:
    assert download.stage == BlockDownloadStage.Idle, "cancelled stage " &
        $download.stage # Explicit no-FIN cancellation retires partial reception.


type SessionClient = object ## Stable native fixture owner borrows only the joined production session.
  transport: Transport
  session: nil ptr BlockDownloadSession
  attempt: nil DownloadSessionAttempt
  stream: NativeStream

proc `=copy`(destination: var SessionClient, source: SessionClient) {.error.}
  ## Callback pointers and transport destruction belong to one fixture owner.

proc sessionEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Route the actual selected token/peer through production code, with no direct receiver access.
  let client = cast[ptr SessionClient](user)
  let borrowed = client.session
  let token = client.attempt
  if borrowed == nil or token == nil:
    assert false, "missing session callback context"
    return # No callback can precede setup or outlive the retained session.
  let session: ptr BlockDownloadSession = borrowed
  if event == 0:
    client.stream = stream
    var limits = DownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: DownloadTimeout(100))
    let wrong = session[].bindStream(token, DownloadPeerId(0), stream, limits, DownloadTick(100))
    assert wrong.error == DownloadSessionError.WrongPeer
    let absent = session[].bindStream(token, token.peer, NativeStream(nil), limits, DownloadTick(100))
    assert absent.streamError == DownloadStreamError.InvalidStream
    limits.readBytes = ByteLimit(0)
    let invalid = session[].bindStream(token, token.peer, stream, limits, DownloadTick(100))
    assert invalid.streamError == DownloadStreamError.InvalidPolicy
    limits.readBytes = ByteLimit(73)
    assert session[].bindStream(token, token.peer, stream, limits, DownloadTick(100)).error ==
        DownloadSessionError.None
    assert session[].bindStream(token, token.peer, stream, limits, DownloadTick(100)).streamError ==
        DownloadStreamError.Busy
    assert session[].finish(token, DownloadAttemptOutcome.Retry,
      DownloadScheduleTick(100)).error == DownloadSessionError.AwaitingClose
    assert session[].discardInput(token).error == DownloadSessionError.AwaitingClose
  else:
    assert not session[].streamEvent(token, DownloadPeerId(0), stream, event)
    assert not session[].streamEvent(token, token.peer, NativeStream(nil), event)
    assert session[].streamEvent(token, token.peer, stream, event)
    if event == 3:
      client.stream = NativeStream(nil)
      assert not session[].streamActive
      assert not session[].streamEvent(token, token.peer, stream,
          3) # Close replay is inert even before terminal acknowledgement.

proc exchangeSession*(session: var BlockDownloadSession, owner: var Services,
    token: DownloadSessionAttempt, expected: array[42, byte], response: seq[byte],
        mode: DownloadTransferMode) =
  ## Reuse the independent wire responder; only the joined controller owns reception/callback identity.
  var client = SessionClient(session: addr session, attempt: token, stream: NativeStream(nil))
  var server = DownloadServer(expected: expected, mode: mode)
  server.response = if mode == Oversized: @[255'u8, 255, 255, 255]
    elif mode == EmptyReply: @[0'u8, 0, 0, 0]
    else: response # Failure bytes remain independent of the joined controller.
  defer:
    client.transport.closeTransport() # Actual native close retires the session's barrier before this borrow leaves scope.
    assert not session.streamActive and client.stream == NativeStream(nil)
    server.transport.closeTransport()
  let cert = getEnv("RAGNAROK_TEST_CERT")
  let key = getEnv("RAGNAROK_TEST_KEY")
  assert server.transport.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
    addr server, verify, serverEvent)
  assert client.transport.openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000",
    addr client, verify, sessionEvent)
  assert client.transport.connectTransport(server.transport.localPort)
  var opened = false
  var settled = false
  for poll in 0..<2000:
    assert server.transport.pollTransport(1) and client.transport.pollTransport(1)
    if not opened and client.transport.authenticatedConnections > 0:
      client.transport.openStream()
      opened = true # The local peer catalog only supplies authenticated transports.
    if mode in [NoFin, Deadline, ResetEvent] and session.receivedBytes == uint64(response.len):
      if mode == Deadline:
        assert session.expire(token, client.stream, DownloadTick(
            200)) # Exact native deadline retains close ownership.
      elif mode == ResetEvent:
        assert session.streamEvent(token, token.peer, client.stream,
            4) # Injected reset-event dispatch does not claim a wire RESET_STREAM.
      else:
        assert session.cancel(token, client.stream) # Cancellation never supplies an implicit response FIN.
      assert session.streamActive and session.busy
      assert session.finish(token, DownloadAttemptOutcome.Retry,
        DownloadScheduleTick(200)).error == DownloadSessionError.AwaitingClose
      settled = true
      break
    if session.stage in [BlockDownloadStage.Ready, BlockDownloadStage.Empty,
        BlockDownloadStage.Failed]:
      settled = true
      break # Bytes/FIN, rather than handshake success, determine the terminal receiver state.
  assert opened and settled and server.requestFin
  if session.streamActive:
    let barred = session.enqueue(token, owner, default(AccumulationCompositionLimits))
    assert barred.error == DownloadSessionError.AwaitingClose # Native close precedes even an invalid preparation policy.


type DownloadResponders* = object ## Two actual TLS identities distinguish target selection from merely naming a peer ID.
  first, second: DownloadServer

proc `=copy`(destination: var DownloadResponders, source: DownloadResponders) {.error.}
  ## Each callback borrows its original fixed server address until explicit close.
proc close*(servers: var DownloadResponders) =
  ## Teardown remains safe after complete, partial or refused startup.
  servers.first.transport.closeTransport()
  servers.second.transport.closeTransport()
proc openResponders*(servers: var DownloadResponders, expected: array[42, byte],
    response: seq[byte], mode = Healthy): bool =
  ## Start independent listeners with a/b certificate identities over the existing wire responder.
  servers.first.expected = expected
  servers.second.expected = expected
  servers.first.response = response
  servers.second.response = response
  servers.first.allowCancelled = true
  servers.second.allowCancelled = true
  servers.first.mode = mode
  servers.second.mode = mode
  if not servers.first.transport.openTransport(true, false, 0,
      getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000",
      addr servers.first, verify, serverEvent): return false # Partial startup retains no listener.
  if not servers.second.transport.openTransport(true, false, 0,
      getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000",
      addr servers.second, verify, serverEvent):
    servers.close()
    return false # Failed second startup must close the already opened first listener.
  true
proc port*(servers: DownloadResponders, second: bool): uint16 =
  ## Return only the bound scalar endpoint selected by the test's explicit identity.
  if second: servers.second.transport.localPort
  else: servers.first.transport.localPort
proc requestCount*(servers: DownloadResponders, second: bool): int =
  ## Count actual exact request+FIN observations, independently of the catalog's chosen token.
  if second: servers.second.requests
  else: servers.first.requests
proc poll*(servers: var DownloadResponders): bool =
  ## Each host test tick polls both listeners once; no background worker or unbounded spin exists.
  servers.first.transport.pollTransport(0) and servers.second.transport.pollTransport(0)

proc unsolicited*(servers: var DownloadResponders): bool =
  ## Emit an independent server-initiated empty stream; the catalog must reject it without touching leased CE input.
  servers.second.transport.openStream()
  let stream = servers.second.stream
  if stream == NativeStream(nil): return false # An actual native stream is required; no fabricated reset count is used.
  wantRead(stream, 0)
  streamFin(stream)
  for turn in 0..<8:
    if not servers.second.transport.pollTransport(
        0): return false # Flush real frames without polling the client catalog.
  true

func resetObserved*(servers: DownloadResponders): bool =
  ## Observe only an actual native directional-reset callback on the independent responder.
  servers.second.reset
