# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real stream backpressure preserves exact bytes and offsets; closed peers cannot raise SIGPIPE.
import std/[assertions, syncio, strutils, nativesocket, oserrors]
import std/posix/posix
import ../../../src/lib/socket_io

proc socketPair(domain, kind, protocol: cint, descriptors: ptr cint): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Create a local stream pair so tests require no ports, external services or timing waits.

let
  GetDescriptorFlags {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  CloseOnExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  SendBuffer {.importc: "SO_SNDBUF", header: "<sys/socket.h>".}: cint

proc testBackpressure() =
  ## Check bounded sends and exact payload reconstruction under real kernel backpressure.
  # Small kernel buffers force a partial write and then backpressure on both supported hosts.
  var pair = [-1.cint, -1.cint]
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
    0, addr pair[0]) == 0
  defer:
    discard posix.close(pair[0])
    discard posix.close(pair[1])
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  assert (fcntl(pair[0], F_GETFL, 0) and O_NONBLOCK) != 0
  assert (fcntl(pair[0], GetDescriptorFlags, 0) and CloseOnExec) != 0
  var capacity = 4096.cint
  assert setOption(pair[0], SocketLevel, SendBuffer, addr capacity, SockLen(sizeof(capacity))) == 0
  let payload = repeat("a\0bc\xff", 65536)
  var offset = 0
  assert writePending(pair[0], payload, offset) == WriteProgress
  assert offset > 0 and offset < payload.len
  # Fill the remaining kernel capacity without draining the peer; no call may block or spin.
  var blocked = false
  for attempt in 0..<128:
    let before = offset
    let written = writePending(pair[0], payload, offset)
    if written == WritePending:
      assert offset == before
      blocked = true
      break
    assert written == WriteProgress
  assert blocked
  var received = ""
  for attempt in 0..<1024:
    # Each turn drains once and sends once, independently checking complete binary payload fidelity.
    var bytes = default(array[4096, char])
    let count = receive(pair[1], addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: received.add(bytes[index])
    else:
      assert count < 0 and retryableSocketError(osLastError())
    let written = writePending(pair[0], payload, offset)
    assert written != WriteFailed
    if received.len == payload.len:
      assert written == WriteComplete
      break
  assert received == payload and offset == payload.len
  var emptyOffset = 0
  assert writePending(-1, "", emptyOffset) == WriteComplete

proc testClosedPeer() =
  ## Check permanent send failure, unchanged cursors and invalid descriptor setup.
  # A broken stream reports failure with its cursor intact instead of terminating the process.
  var pair = [-1.cint, -1.cint]
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
    0, addr pair[0]) == 0
  defer: discard posix.close(pair[0])
  assert nonblocking(pair[0])
  discard posix.close(pair[1])
  var offset = 0
  assert writePending(pair[0], "closed", offset) == WriteFailed
  assert offset == 0
  assert not nonblocking(-1)

testBackpressure()
testClosedPeer()
echo "socket io ok"
