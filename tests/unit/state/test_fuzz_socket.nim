# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real AF_UNIX exchanges exercise bounded ticks, fragmented frames and repeated isolated sessions.
import std/syncio
import ../../support/fuzz_protocol_context
import ../../../src/state/store
include ../../../src/app/fuzz_socket
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
  assert result >= 0
  var address = default(LocalAddress)
  address.sun_family = typeof(address.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): address.sun_len = uint8(sizeof(address)) # Use the same native platform layout.
  for index, c in path: address.sun_path[index] = c # Policy-proven test path fits the common bound.
  assert connectSocket(result, addr address, SockLen(sizeof(address))) == 0
  assert nonblocking(result)
proc sendFrame(server: var FuzzSocket, peer: cint, message: FuzzMessage) =
  ## Deliberately deliver one byte per tick, including the fragmented length prefix.
  let encoded = message.encodeFuzzFrame(ByteLimit(uint64(server.config.limits.bytes)+4)).value
  for octet in encoded:
    var one = octet
    assert sendBytes(peer, addr one, 1, 0) == 1
    server.tick() # Tiny deterministic requests never depend on stream packet coalescing.
proc readFrame(server: var FuzzSocket, peer: cint): FuzzMessage =
  ## Bound real socket reads and decode the entire response through a fresh independent reader lifetime.
  var reader = initFuzzFrameReader(fuzzProtocolTestLimits())
  for attempt in 0..<10000:
    server.tick()
    var input = default(array[4096, byte])
    let count = receive(peer, addr input[0], csize_t(input.len), 0)
    if count > 0:
      let got = reader.feed(input.toOpenArray(0, count-1))
      assert got.error == FuzzSessionError.None and got.value.consumed == count
      if got.value.complete: return got.value.message # No prefix or partial response counts as success.
    else:
      assert count < 0 and osLastError() in [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK),
          OSErrorCode(EINTR)]
      discard pauseMicros(100) # Retry only transient OS scheduling; EOF is a failure here.
  assert false, "bounded response wait expired"
  default(FuzzMessage)
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
    assert server.connected and server.generation == 1
    server.sendFrame(peer, hello)
    assert server.readFrame(peer).fuzzPeer.value.name == "socket-test"
    server.sendFrame(peer, init)
    assert server.hasRequest
    let ticket = server.request
    assert ticket.requestMessage.value.fuzzInfo.value.kind == FuzzKind.Initialize
    assert server.respond(ticket, root)
    assert server.readFrame(peer).copyFuzzMessage(limits.bytes).value == root.copyFuzzMessage(
        limits.bytes).value
    var importWire = newSeq[byte](305)
    importWire[0] = 3
    server.sendFrame(peer, decodeFuzzMessage(importWire, limits).value)
    assert server.hasRequest
    var longText = newString(4096)
    for index in 0..<longText.len: longText[index] = 'x' # Force output beyond the per-tick write budget.
    let rejected = newFuzzError(longText, limits).value
    assert server.respond(server.request, rejected)
    server.tick()
    assert server.output.len > 0 and server.offset <= IoBytes # Partial writes retain the remaining frame.
    assert server.readFrame(peer).fuzzText.value == longText
    discard posix.close(peer)
    server.tick()
    assert not server.connected and not server.hasRequest
    let next = client(path)
    server.tick()
    assert server.connected and server.generation == 2
    server.sendFrame(next, init)
    assert not server.connected # Reconnection resets the handshake requirement.
    discard posix.close(next)
    let malformed = client(path)
    server.tick()
    var bad = [1'u8, 0, 0, 0, 6]
    assert sendBytes(malformed, addr bad[0], csize_t(bad.len), 0) == bad.len
    server.tick()
    assert not server.connected
    discard posix.close(malformed)
    let idle = client(path)
    server.tick()
    server.deadline = 0
    server.tick()
    assert not server.connected # Same timeout branch retires an idle or partial request.
    discard posix.close(idle)
    let broken = client(path)
    server.tick()
    server.sendFrame(broken, hello)
    discard server.readFrame(broken)
    server.sendFrame(broken, init)
    let outstanding = server.request
    discard posix.close(broken)
    assert server.respond(outstanding, root)
    server.tick()
    assert not server.connected # A broken response pipe does not deliver SIGPIPE to the host.
    server.close()
    server.close()
    assert readStatus(path.toCString(), status) != 0
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
  echo "PASS JAM fuzzer socket: bounded IO, ticket handoff, reconnect and owned cleanup"
try:
  main() # Filesystem/IO failures are failed native tests, never ignored protocol outcomes.
except:
  quit(2)
