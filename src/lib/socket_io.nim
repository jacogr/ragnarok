# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Nonblocking POSIX stream socket mechanics shared by the optional services.
## Descriptors and borrowed buffers remain caller-owned. No scheduler, retry loop or global
## signal handler is installed; callers retain admission, deadlines, budgets and cleanup.

import std/[nativesocket, oserrors]
import std/posix/posix

type WriteStatus* = enum
  ## One bounded send either drains, advances, defers or fails the caller's pending bytes.
  WritePending, WriteProgress, WriteComplete, WriteFailed

proc socket*(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Create a descriptor; the caller owns configuration and cleanup, including setup failure.

proc bindSocket*(fd: cint, address: pointer, size: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
  ## Bind a caller-owned socket using an initialized address borrowed for this syscall only.

proc listenSocket*(fd, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
  ## Enable admission after the caller applies its address and permission policy.

proc acceptSocket*(fd: cint, address, size: nil pointer): cint {.importc: "accept",
    header: "<sys/socket.h>".}
  ## Accept once without peer metadata; the caller must configure or close the new descriptor.

proc connectSocket*(fd: cint, address: pointer, size: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## Start one connection attempt; callers retain EINPROGRESS and completion handling.

proc receive*(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Read once into caller-bounded borrowed storage, returning the native count or error.

proc nativeSend(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Borrow the initialized byte extent for one native send without retaining its pointer.

proc setOption*(fd, level, option: cint, value: pointer,
    size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
  ## Apply one socket option using caller-owned scalar storage.

proc parseAddress*(family: cint, text: cstring, output: pointer): cint {.importc: "inet_pton",
    header: "<arpa/inet.h>".}
  ## Parse a numeric literal into native address storage without DNS or retained pointers.

proc networkPort*(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
  ## Convert a host-order port to network byte order.

let
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  SocketLevel* {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
  ReuseAddress* {.importc: "SO_REUSEADDR", header: "<sys/socket.h>".}: cint
when defined(macosx):
  # Darwin requires descriptor-level SIGPIPE suppression before any send.
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint
else:
  # Linux suppresses SIGPIPE on each send, leaving the process signal policy untouched.
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint

proc nonblocking*(fd: cint): bool =
  ## Preserve existing flags while enabling nonblocking IO, close-on-exec and safe sends.
  ## Failure retains ownership with the caller, which must close the partially configured fd.
  let flags = fcntl(fd, F_GETFL, 0)
  let descriptorFlags = fcntl(fd, GetFd, 0)
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFd, descriptorFlags or CloseExec) < 0: return false
  when defined(macosx):
    # A descriptor that cannot suppress SIGPIPE is unsuitable for these optional services.
    var enabled = 1.cint
    if setOption(fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) != 0:
      return false
  true

proc listenLoopback*(port: uint16, backlog: cint): cint =
  ## Open a configured IPv4 loopback listener. A negative result owns no descriptor.
  let family = cint(ord(nativesocket.AF_INET))
  let fd = socket(family, cint(ord(nativesocket.SOCK_STREAM)), 0)
  if fd < 0: return -1
  var reuse = 1.cint
  var address = default(Sockaddr_in)
  address.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  address.sin_port = networkPort(port)
  when defined(macosx):
    # Darwin includes the sockaddr extent.
    address.sin_len = uint8(sizeof(Sockaddr_in))
  var loopback = "127.0.0.1"
  if setOption(fd, SocketLevel, ReuseAddress, addr reuse, SockLen(sizeof(reuse))) != 0 or
      not nonblocking(fd) or parseAddress(family, loopback.toCString(), addr address.sin_addr) != 1 or
      bindSocket(fd, addr address, SockLen(sizeof(address))) != 0 or listenSocket(fd, backlog) != 0:
    discard posix.close(fd) # The caller receives only a fully configured listener.
    return -1
  fd

proc retryableSocketError*(error: OSErrorCode): bool =
  ## Backpressure and interruption defer work to a later dispatcher turn without spinning.
  error in [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(EINTR)]

proc sendBytes*(fd: cint, data: pointer, size: csize_t, flags = 0.cint): int =
  ## Send once with SIGPIPE suppressed; Darwin callers must first configure the descriptor.
  when defined(macosx):
    # SO_NOSIGPIPE was installed by nonblocking; no process-wide handler is required.
    nativeSend(fd, data, size, flags)
  else:
    # Per-send suppression also covers Unix domain streams on Linux.
    nativeSend(fd, data, size, flags or NoSignal)

proc writePending*(fd: cint, data: pointer, length: int, offset: var int): WriteStatus {.
    requires: length >= 0 and offset >= 0 and offset <= length.} =
  ## Send at most once from the borrowed initialized extent, advancing only on actual progress.
  ## The caller must keep the same bytes until drained; deadlines and queue reset remain its policy.
  if offset == length: return WriteComplete # No syscall or pointer arithmetic for an empty suffix.
  let sent = sendBytes(fd, cast[pointer](cast[uint](data) + uint(offset)),
    csize_t(length - offset))
  if sent > 0:
    # The kernel accepted a prefix of precisely the remaining extent.
    offset += sent
    if offset == length: WriteComplete
    else: WriteProgress
  elif sent < 0 and retryableSocketError(osLastError()):
    # Capture errno before returning; transient failure preserves the exact suffix.
    WritePending
  else:
    # Zero progress or a permanent error lets the service retire only its own connection.
    WriteFailed

proc writePending*(fd: cint, data: string, offset: var int): WriteStatus {.
    requires: offset >= 0 and offset <= data.len.} =
  ## Borrow short or heap string storage only during this send; no NUL terminator is needed.
  let bytes = data.readRawData()
  writePending(fd, bytes, data.len, offset)
