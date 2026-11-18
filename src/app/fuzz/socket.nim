# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The fuzzer listener owns one live session and hands execution tickets to the
## host outside I/O. A Reader/Writer task owns the accepted connection; only
## framing and validated session state are kept in the dispatcher.
## Path ownership and permissions are tied to the exact bound Unix socket.

import std/[nativesocket, strutils, assertions]
from std/ioring import Deadline, afterMs, expired
import std/posix/posix
import ../../state/fuzz/[protocol as fuzz_protocol, session as fuzz_session]
import ../../codec/bounded
import ../../management/file_status
import ../../lib/[socket_io, utf8]
import ./stream

type
  LocalAddress = object
    ## POSIX local-address prefix uses a common 104-byte pathname extent; Linux accepts this shorter bounded address.
    when defined(macosx):
      sun_len: uint8
      sun_family: uint8
    else:
      sun_family: cushort
    sun_path: array[104, char]
  FuzzSocketConfig* = object ## Trusted host policy supplies the target declaration, wire bounds and absolute exchange deadline.
    path*: string
    timeoutMs*: int
    peer*: FuzzPeer
    limits*: FuzzLimits
  FuzzSocket* = object ## One listener and one connection own all descriptors, frames and pending request identity.
    opened, bound, connected, waiting: bool
    fd: cint
    stream: FuzzStream
    identity: FileStatus
    config: FuzzSocketConfig
    generation: uint64
    deadline: Deadline
    reader: FuzzFrameReader
    session: FuzzSession
    ticket: FuzzRequest

proc effectiveUid(): uint32 {.importc: "geteuid", header: "<unistd.h>".}
  ## Socket parent ownership is checked against the actual effective user.

proc removeSocket(server: FuzzSocket) =
  ## Replacement paths and files never inherit cleanup authority from this lifetime.
  if server.bound:
    var current = default(FileStatus)
    var path = server.config.path
    if readStatus(path.toCString(), current) == 0 and S_ISSOCK(Mode(current.st_mode)) and
        current.st_dev == server.identity.st_dev and current.st_ino == server.identity.st_ino:
      discard unlink(path.toCString()) # Exact inode ownership confines removal to the bound socket.

proc `=copy`*(destination: var FuzzSocket, source: FuzzSocket) {.error.}
  ## Descriptor ownership cannot be copied between hosts.

proc `=dup`*(source: FuzzSocket): FuzzSocket {.error.}
  ## Implicit duplication is also forbidden.

proc `=wasMoved`*(server: var FuzzSocket) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  server.opened = false
  server.bound = false
  server.connected = false
  server.waiting = false
  server.fd = -1
  `=wasMoved`(server.stream)
  `=wasMoved`(server.config)
  `=wasMoved`(server.reader)
  `=wasMoved`(server.session)
  `=wasMoved`(server.ticket)

proc `=destroy`*(server: FuzzSocket) =
  ## Default/moved owners never close descriptor zero; partial startup releases every acquired resource.
  `=destroy`(server.stream)
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  `=destroy`(server.config)
  `=destroy`(server.reader)
  `=destroy`(server.session)
  `=destroy`(server.ticket)

proc disconnect*(server: var FuzzSocket) =
  ## Retire a connection and all its tickets while leaving the listener ready for a new session.
  server.stream = default(FuzzStream)
  server.connected = false
  server.waiting = false
  server.session.close()
  server.reader = default(FuzzFrameReader)
  server.ticket = default(FuzzRequest)

proc close*(server: var FuzzSocket) =
  ## Explicit shutdown is idempotent and uses the same inode-limited cleanup as ARC retirement.
  server.disconnect()
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  server.opened = false
  server.bound = false
  server.config = default(FuzzSocketConfig)

func connected*(server: FuzzSocket): bool =
  ## Backend state belongs to an active connection only.
  server.connected

func generation*(server: FuzzSocket): uint64 =
  ## Each accepted connection gets a distinct generation; exhaustion stops further admission.
  server.generation

func hasRequest*(server: FuzzSocket): bool =
  ## A pending execution ticket is distinct from partial input or an automatic handshake reply.
  server.connected and server.waiting

func request*(server: FuzzSocket): FuzzRequest {.inline, requires: server.hasRequest.} =
  ## Borrow immutable request authority for execution outside the transport tick.
  server.ticket

func negotiatedFeatures*(server: FuzzSocket): uint32 =
  ## The host activates optional backend behavior only after the actual handshake intersection.
  if server.connected: server.session.negotiatedFeatures else: 0'u32

proc start*(server: var FuzzSocket, config: FuzzSocketConfig): bool =
  ## Reject bad policy and existing paths before opening a bounded private listener.
  if server.opened or server.bound or config.timeoutMs <= 0 or config.timeoutMs > 3600000:
    return false
  if initFuzzSession(config.peer, config.limits).error != FuzzSessionError.None or
      uint64(config.limits.bytes) > uint64(high(int)-4): return false
  let path = config.path
  if path.len == 0 or path.len > 103 or path[0] != '/' or path.endsWith('/') or not validUtf8(path):
    return false
  for c in path:
    if ord(c) < 32 or ord(c) == 127: return false # No native truncation or ambiguous control-bearing path.
  let slash = path.rfind('/')
  var directory = if slash == 0: "/" else: path.substr(0, slash-1)
  var parent = default(FileStatus)
  if readStatus(directory.toCString(), parent) != 0 or not S_ISDIR(Mode(parent.st_mode)) or
      uint32(parent.st_uid) != effectiveUid() or (uint32(parent.st_mode) and 0o077'u32) != 0:
    return false # The bind-to-chmod interval remains inside a private directory.
  var address = default(LocalAddress)
  address.sun_family = typeof(address.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): address.sun_len = uint8(sizeof(address)) # Native Darwin requires its address extent.
  for index, c in path: address.sun_path[index] = c # The zero-initialized terminator remains within the common bound.
  let fd = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if fd < 0: return false
  server.fd = fd
  server.opened = true
  if not nonblocking(fd) or bindSocket(fd, addr address, SockLen(sizeof(address))) != 0:
    server.close()
    return false # An existing path remains untouched, including another live socket.
  server.config = config
  var nativePath = path
  if readStatus(nativePath.toCString(), server.identity) != 0:
    server.close()
    return false # Never assume ownership without an observed native inode.
  server.bound = true
  if chmod(nativePath.toCString(), Mode(0o600)) != 0 or listenSocket(fd, 1) != 0:
    server.close()
    return false # Partial successful startup retires its own path and descriptor.
  true

proc queue(server: var FuzzSocket, message: FuzzMessage): bool =
  ## A complete output frame takes the one available Writer credit.
  let encoded = message.encodeFuzzFrame(ByteLimit(uint64(server.config.limits.bytes)+4))
  if encoded.error != FuzzError.None: return false
  var output = encoded.value
  server.stream.send(output)

proc respond*(server: var FuzzSocket, ticket: FuzzRequest, message: FuzzMessage): bool =
  ## Submit only a genuine host outcome matching the still-live ticket; internal failure uses disconnect instead.
  if not server.hasRequest: return false
  let response = server.session.respond(ticket, message)
  if response.error != FuzzSessionError.None or not server.queue(response.value):
    server.disconnect()
    return false # Invalid host responses cannot reach the socket as consensus errors.
  server.waiting = false
  server.ticket = default(FuzzRequest)
  true

proc tick*(server: var FuzzSocket) =
  ## Admit one connection and handle at most one bounded input chunk per turn.
  if not server.opened: return
  pollFuzzStreams()
  if not server.connected:
    if server.generation == high(uint64): return # A reused process must never wrap a session identity.
    let fd = acceptSocket(server.fd, nil, nil)
    if fd < 0: return
    let deadline = afterMs(server.config.timeoutMs)
    if not nonblocking(fd) or not server.stream.start(fd, deadline, server.config.timeoutMs):
      discard posix.close(fd) # Ownership stays here when stream setup fails.
      return
    server.connected = true
    inc server.generation
    server.deadline = deadline
    server.reader = initFuzzFrameReader(server.config.limits)
    server.session = initFuzzSession(server.config.peer, server.config.limits).value
  if server.stream.takeWritten(server.deadline):
    server.stream.receiveNext() # A complete flush is the only event that renews the deadline.
  if server.stream.finished or expired(server.deadline):
    server.disconnect()
    return # Retire partial input, output and execution authority together.
  var bytes = default(array[IoBytes, byte])
  var buffered = false
  let count = server.stream.takeInput(bytes, buffered)
  if count == 0: return
  let decoded = server.reader.feed(bytes.toOpenArray(0, count - 1))
  if decoded.error != FuzzSessionError.None or decoded.value.consumed != count or
      (decoded.value.complete and buffered):
    server.disconnect()
    return # Coalesced pipelining cannot create hidden queued work.
  if not decoded.value.complete:
    server.stream.receiveNext()
    return # Partial reads keep the original deadline.
  let dispatched = server.session.receive(decoded.value.message)
  if dispatched.error != FuzzSessionError.None:
    server.disconnect()
    return # Malformed ordering or profile failures close without a protocol Error reply.
  case dispatched.value.kind
  of FuzzDispatchKind.Reply:
    if not server.queue(dispatched.value.reply): server.disconnect()
  of FuzzDispatchKind.Execute:
    server.ticket = dispatched.value.request
    server.waiting = true # The task remains parked until the host submits a genuine response.
