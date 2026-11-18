# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real AF_UNIX exchanges exercise bounded ticks, fragmented frames and repeated isolated sessions.

import std/[syncio, oserrors, monotimes]
import std/ioring as reactor
from ../../../src/lib/stop_signal import ignorePipeSignal
import ../../support/fuzz_protocol_context
import ../../../src/state/store
include ../../../src/app/fuzz/socket

proc connectSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## A real client connects through the listener rather than bypassing descriptor admission.

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Isolate filesystem witnesses across concurrently running suite processes.

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bound retries without a blocking receive on the test client.

proc client(path: string): cint =
  ## Connect one real local peer and make its subsequent IO nonblocking.
  result = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert result >= 0, "create the test client socket"
  var address = default(LocalAddress)
  address.sun_family = typeof(address.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): address.sun_len = uint8(sizeof(address)) # Use the same native platform layout.
  for index, c in path: address.sun_path[index] = c # Policy-proven test path fits the common bound.
  assert connectSocket(result, addr address, SockLen(sizeof(address))) == 0, "connect the test client"
  assert nonblocking(result), "make the test client nonblocking"

proc sendFrame(server: var FuzzSocket, peer: cint, message: FuzzMessage) =
  ## Deliberately deliver one byte per tick, including the fragmented length prefix.
  let encoded = message.encodeFuzzFrame(ByteLimit(uint64(server.config.limits.bytes)+4)).value
  let deadline = afterMs(3000)
  for offset, octet in encoded:
    var one = octet
    while true:
      assert not expired(deadline), "fragmented peer send deadline at byte " & $offset
      let sent = sendBytes(peer, addr one, 1)
      if sent == 1: break
      let error = osLastError()
      assert sent < 0 and retryableSocketError(error), "fragmented peer send failed at byte " &
          $offset & " with errno " & $int32(error)
      server.tick() # A nonblocking AF_UNIX peer can run out of queue space before the Reader runs.
      discard pauseMicros(100)
    server.tick() # Offer each byte separately, including the length prefix.
    discard pauseMicros(100)

proc readFrame(server: var FuzzSocket, peer: cint): FuzzMessage =
  ## Bound real socket reads and decode the entire response through a fresh independent reader lifetime.
  var reader = initFuzzFrameReader(fuzzProtocolTestLimits())
  for attempt in 0..<10000:
    server.tick()
    var input = default(array[4096, byte])
    let count = receive(peer, addr input[0], csize_t(input.len), 0)
    if count > 0:
      let got = reader.feed(input.toOpenArray(0, count-1))
      assert got.error == FuzzSessionError.None and got.value.consumed == count, "decode the complete response prefix"
      if got.value.complete: return got.value.message # No prefix or partial response counts as success.
    else:
      assert count < 0 and osLastError() in [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK),
          OSErrorCode(EINTR)], "wait for response without EOF or a permanent socket error"
      discard pauseMicros(100) # Retry only transient OS scheduling; EOF is a failure here.
  assert false, "bounded response wait expired"
  default(FuzzMessage)

proc awaitRequest(server: var FuzzSocket): FuzzRequest =
  ## Wait for the dispatcher to receive a complete frame from the worker.
  for attempt in 0..<5000:
    server.tick()
    if server.hasRequest: return server.request
    discard pauseMicros(100)
  assert false, "bounded execution ticket wait expired"
  default(FuzzRequest)

proc awaitDisconnect(server: var FuzzSocket) =
  ## Task retirement is asynchronous until the dispatcher sees completion.
  for attempt in 0..<5000:
    server.tick()
    if not server.connected: return
    discard pauseMicros(100)
  assert false, "bounded session retirement wait expired"

let SendBuffer {.importc: "SO_SNDBUF", header: "<sys/socket.h>".}: cint

proc blockedWriter(stopEarly: bool) =
  ## Either drain or stop while a real Writer holds output credit behind an unread Unix peer.
  proc socketPair(domain, kind, protocol: cint, fds: ptr cint): cint {.
      importc: "socketpair", header: "<sys/socket.h>".}
  var pair = default(array[2, cint])
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0,
      addr pair[0]) == 0
  defer: discard posix.close(pair[1])
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  var capacity = 4096.cint
  assert setOption(pair[0], SocketLevel, SendBuffer, addr capacity, SockLen(sizeof(capacity))) == 0
  var stream = default(FuzzStream)
  var deadline = afterMs(30000)
  assert stream.start(pair[0], deadline, 30000)
  var octet = 42'u8
  assert sendBytes(pair[1], addr octet, 1) == 1
  var chunk = default(array[IoBytes, byte])
  var buffered = false
  var count = 0
  for attempt in 0..<1000:
    pollFuzzStreams()
    count = stream.takeInput(chunk, buffered)
    if count != 0: break
    discard pauseMicros(1000)
  assert count == 1 and chunk[0] == octet, "worker reads the socket pair witness byte"
  const ResponseBytes = 65536
  var response = newSeq[byte](ResponseBytes)
  for index in 0..<ResponseBytes: response[index] = byte(index mod 251)
  assert stream.send(response), "submit the large response to the Writer"
  for attempt in 0..<1000:
    pollFuzzStreams()
    count = receive(pair[1], addr octet, 1, 0)
    if count == 1: break # The kernel received only a prefix; leave the rest of the credit blocked.
    discard pauseMicros(1000)
  assert count == 1 and octet == 0 and not stream.takeWritten(deadline),
      "Writer makes partial progress and remains blocked"
  if stopEarly:
    let started = getMonoTime().ticks
    stream = default(FuzzStream)
    assert (getMonoTime().ticks - started) div 1000000 < 1000,
        "blocked Writer joins without waiting for the configured deadline"
    return
  discard pauseMicros(500000) # More than one Linux readiness wait; no reply has timed out.
  assert not stream.finished and not stream.takeWritten(deadline),
      "a blocked reply retains credit through a readiness timeout"
  var consumed = 1 # The first byte was checked before deliberately blocking the Writer.
  let receiveDeadline = afterMs(3000)
  while consumed < ResponseBytes:
    assert not expired(receiveDeadline), "blocked Writer resumes within the exchange budget"
    pollFuzzStreams()
    count = receive(pair[1], addr chunk[0], csize_t(chunk.len), 0)
    if count > 0:
      assert count <= ResponseBytes - consumed, "Writer does not repeat a partial write"
      for index in 0..<count:
        assert chunk[index] == byte((consumed + index) mod 251), "resumed Writer keeps byte order"
      consumed += count
    else:
      assert count < 0 and retryableSocketError(osLastError()), "drain the resumed Writer"
      discard pauseMicros(100)
  while not stream.takeWritten(deadline):
    assert not expired(receiveDeadline), "complete flush releases the Writer's credit"
    pollFuzzStreams()
    discard pauseMicros(100)

proc main() {.raises.} =
  ## Synthetic host replies test transport only; no test claims to have executed a JAM transition.
  let limits = fuzzProtocolTestLimits()
  let identity = FuzzPeer(protocol: 1, jam: FuzzVersion(major: 0, minor: 8), name: "socket-test")
  let hello = newFuzzPeer(identity, limits).value
  let empty = decodeFuzzMessage(@[5'u8, 0], limits).value
  let root = newFuzzRoot(empty.fuzzState.value.commitment.root, limits).value
  var initialize = newSeq[byte](300)
  initialize[0] = 1
  let init = decodeFuzzMessage(initialize, limits).value
  var directory = "/tmp/ragnarok-fuzz-" & $processId()
  var path = directory & "/target.sock"
  assert mkdir(directory.toCString(), Mode(0o700)) == 0
  let config = FuzzSocketConfig(path: path, timeoutMs: 5000, peer: identity, limits: limits)
  block lifecycle:
    var server = default(FuzzSocket)
    assert not server.connected and not server.hasRequest
    var wrong = config
    wrong.path = "relative.sock"
    assert not server.start(wrong)
    wrong.path = "/tmp/shared-fuzz.sock"
    assert not server.start(wrong)
    wrong = config
    wrong.timeoutMs = 0
    assert not server.start(wrong)
    assert server.start(config)
    assert not server.start(config)
    var status = default(FileStatus)
    assert readStatus(path.toCString(), status) == 0 and (uint32(status.st_mode) and 0o777'u32) == 0o600
    var competitor = default(FuzzSocket)
    assert not competitor.start(config)
    assert readStatus(path.toCString(), status) == 0 # Refused competing bind cannot unlink our socket.
    let peer = client(path)
    server.tick()
    assert server.connected and server.generation == 1, "accept the first peer"
    server.sendFrame(peer, hello)
    assert server.readFrame(peer).fuzzPeer.value.name == "socket-test"
    server.sendFrame(peer, init)
    let ticket = server.awaitRequest()
    assert ticket.requestMessage.value.fuzzInfo.value.kind == FuzzKind.Initialize
    assert server.respond(ticket, root), "submit initialization reply"
    assert server.readFrame(peer).copyFuzzMessage(limits.bytes).value == root.copyFuzzMessage(
        limits.bytes).value
    var importWire = newSeq[byte](305)
    importWire[0] = 3
    server.sendFrame(peer, decodeFuzzMessage(importWire, limits).value)
    let importTicket = server.awaitRequest()
    var longText = newString(4096)
    for index in 0..<longText.len: longText[index] = 'x' # Force a reply to span multiple Writer chunks.
    let rejected = newFuzzError(longText, limits).value
    assert server.respond(importTicket, rejected), "submit the multi-chunk reject reply"
    assert server.readFrame(peer).fuzzText.value == longText, "read the complete multi-chunk reply"
    discard posix.close(peer)
    server.awaitDisconnect()
    assert not server.hasRequest
    let next = client(path)
    server.tick()
    assert server.connected and server.generation == 2, "accept the new peer after EOF"
    server.sendFrame(next, init)
    server.awaitDisconnect() # Reconnection resets the handshake requirement.
    discard posix.close(next)
    let malformed = client(path)
    server.tick()
    var bad = [1'u8, 0, 0, 0, 6]
    assert sendBytes(malformed, addr bad[0], csize_t(bad.len), 0) == bad.len
    server.awaitDisconnect()
    discard posix.close(malformed)
    let idle = client(path)
    server.tick()
    server.deadline = afterMs(0)
    server.awaitDisconnect() # An expired dispatcher deadline retires a pending Reader.
    discard posix.close(idle)
    let broken = client(path)
    server.tick()
    server.sendFrame(broken, hello)
    discard server.readFrame(broken)
    server.sendFrame(broken, init)
    let outstanding = server.awaitRequest()
    discard posix.close(broken)
    assert server.respond(outstanding, root), "submit the reply after peer close"
    server.awaitDisconnect() # A broken response pipe does not deliver SIGPIPE to the host.
    server.close()
    server.close()
    assert readStatus(path.toCString(), status) != 0
  block movedPath:
    # Source cleanup cannot unlink the destination's live bound pathname.
    var source = default(FuzzSocket)
    assert source.start(config)
    var destination = move(source)
    assert not source.opened and not source.bound
    source.close()
    var movedStatus = default(FileStatus)
    assert readStatus(path.toCString(), movedStatus) == 0 and S_ISSOCK(Mode(movedStatus.st_mode))
    destination.close()
    assert readStatus(path.toCString(), movedStatus) != 0
  block destructorCleanup:
    var server = default(FuzzSocket)
    assert server.start(config) # ARC retirement removes the exact bound inode without an explicit close.
  var status = default(FileStatus)
  assert readStatus(path.toCString(), status) != 0
  block replacement:
    var server = default(FuzzSocket)
    assert server.start(config)
    assert unlink(path.toCString()) == 0
    writeFile(path, "replacement")
    server.close()
    assert readFile(path) == "replacement" # Cleanup cannot delete a replacement file at the same pathname.
  assert unlink(path.toCString()) == 0
  assert rmdir(directory.toCString()) == 0
  blockedWriter(false)
  blockedWriter(true)
  echo "PASS JAM fuzzer socket: bounded IO, ticket handoff, reconnect and owned cleanup"
assert ignorePipeSignal(), "configure SIGPIPE handling before the Writer runs"
try:
  main() # Filesystem/IO failures are failed native tests, never ignored protocol outcomes.
except:
  quit(2)

# Move a genuine live Reader with the listener, then close the moved-from owner.
block movedSocket:
  var path = "/tmp/ragnarok-fuzz-move-" & $processId()
  assert mkdir(path.toCString(), Mode(0o700)) == 0
  var socketPath = path & "/target.sock"
  let policy = FuzzSocketConfig(path: socketPath, timeoutMs: 30000,
    peer: FuzzPeer(protocol: 1, jam: FuzzVersion(major: 0, minor: 8), name: "moved"),
    limits: fuzzProtocolTestLimits())
  var source = default(FuzzSocket)
  assert source.start(policy)
  let peer = client(socketPath)
  source.tick()
  assert source.connected
  var destination = move(source)
  source.close()
  assert destination.connected and fcntl(destination.fd, F_GETFL) >= 0
  destination.sendFrame(peer, newFuzzPeer(policy.peer, policy.limits).value)
  assert destination.readFrame(peer).fuzzPeer.value.name == "moved"
  let started = getMonoTime().ticks
  destination.close()
  assert (getMonoTime().ticks - started) div 1000000 < 1000, "close joins without waiting for the configured deadline"
  var octet = 0'u8
  assert receive(peer, addr octet, 1, 0) == 0, "moved peer sees EOF after destination close"
  discard posix.close(peer)
  assert rmdir(path.toCString()) == 0

reactor.shutdown()
