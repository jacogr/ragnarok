# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native descriptor setup and closed-peer signal suppression for one-shot fixture sends.

import std/[assertions, syncio, nativesocket]
import std/posix/posix
import ../../../src/lib/socket_io

proc socketPair(domain, kind, protocol: cint, descriptors: ptr cint): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Create a local stream pair so tests require no ports, external services or timing waits.

let
  GetDescriptorFlags {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  CloseOnExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint

proc testClosedPeer() =
  ## Check descriptor setup and that a failed native send cannot terminate the process.
  var pair = [-1.cint, -1.cint]
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
    0, addr pair[0]) == 0
  defer: discard posix.close(pair[0])
  assert nonblocking(pair[0])
  assert (fcntl(pair[0], F_GETFL, 0) and O_NONBLOCK) != 0
  assert (fcntl(pair[0], GetDescriptorFlags, 0) and CloseOnExec) != 0
  discard posix.close(pair[1])
  let payload = "closed"
  assert sendBytes(pair[0], payload.readRawData(), csize_t(payload.len)) < 0
  assert not nonblocking(-1)

testClosedPeer()
echo "socket io ok"
