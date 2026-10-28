# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-threaded bounded POSIX readiness and loopback UDP for the maintained QUIC adapter. No
## pending syscall retains buffers; unregister precedes descriptor close and descriptor reuse.
##
## Exposes dispatcher and UDP endpoint ownership, descriptor registration, bounded
## wait/send/receive and explicit close operations.

import std/assertions
import std/oserrors
import std/nativesocket
import std/syncio
import std/posix/posix

const
  SocketHeader = "<sys/socket.h>"
  AddressHeader = "<netinet/in.h>"
  PollHeader = "<poll.h>"

type
  # Header-defined IPv6 storage avoids transcribing an OS-specific sockaddr layout.
  Address6 {.importc: "struct sockaddr_in6", header: AddressHeader, bycopy.} = object
    when defined(macosx):
      sin6_len: uint8 # Only BSD socket addresses have a length byte.
    sin6_family: TSa_Family
    sin6_port: uint16
    sin6_addr: Address6Bytes
  # Native IPv6 bytes are copied only while the syscall's address remains on the stack.
  Address6Bytes {.importc: "struct in6_addr", header: AddressHeader, bycopy.} = object
    s6_addr: array[16, byte]
  # poll owns no kernel registration; each call borrows this initialized fixed array synchronously.
  PollEntry {.importc: "struct pollfd", header: PollHeader, bycopy.} = object
    fd: cint
    events, revents: cshort
  # Shared dispatcher metadata owns no socket and has no reference back to its endpoints.
  DispatcherState = object
    descriptors: array[2, cint]
    count: int
    closed: bool
  Dispatcher* = ref DispatcherState ## Up to two endpoints share one bounded wait; callers retire endpoints before closing it.
  UdpEndpoint* = object ## Explicit open flag makes a default endpoint harmless even though descriptor zero is valid.
    descriptor: cint
    opened, ipv6: bool
    portValue: uint16
    registration: nil Dispatcher
  Ready* = object ## One copied readiness event; no pointer into poll's temporary storage escapes.
    descriptor*: cint
    failed*: bool

# Socket creation/configuration calls bind public OS headers, never compiler/runtime internals.
proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: SocketHeader.}
# Addresses are borrowed synchronously and use the family-specific byte extent.
proc bindSocket(fd: cint, address: pointer, length: SockLen): cint {.importc: "bind",
    header: SocketHeader.}
# Query the actual assigned port after a successful ephemeral bind.
proc socketName(fd: cint, address: pointer, length: ptr SockLen): cint {.importc: "getsockname",
    header: SocketHeader.}
# Datagram syscalls never retain caller/native-library buffers after returning.
proc sendTo(fd: cint, data: pointer, length: csize_t, flags: cint, address: pointer,
    addressLength: SockLen): int {.importc: "sendto", header: SocketHeader.}
# One nonblocking datagram read, with a copied source address for native-language scope validation.
proc receiveFrom(fd: cint, data: pointer, length: csize_t, flags: cint, address: pointer,
    addressLength: ptr SockLen): int {.importc: "recvfrom", header: SocketHeader.}
# Native byte-order helpers use the public platform declarations.
proc hostPort(port: uint16): uint16 {.importc: "ntohs", header: AddressHeader.}
# Convert ports for either loopback family.
proc networkPort(port: uint16): uint16 {.importc: "htons", header: AddressHeader.}
# IPv4 address conversion remains independent of host endianness.
proc networkAddress(address: uint32): uint32 {.importc: "htonl", header: AddressHeader.}
# A bounded readiness wait borrows at most two entries and never creates worker threads.
proc poll(entries: ptr PollEntry, count: culong, timeout: cint): cint {.importc: "poll",
    header: PollHeader.}

let
  # Descriptor inheritance constants are absent from this nightly's POSIX convenience exports.
  GetFdFlags {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFdFlags {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  # Header constants retain the platform's actual poll flags instead of assuming numeric values.
  PollRead {.importc: "POLLIN", header: PollHeader.}: cshort
  PollError {.importc: "POLLERR", header: PollHeader.}: cshort
  PollHangup {.importc: "POLLHUP", header: PollHeader.}: cshort
  PollInvalid {.importc: "POLLNVAL", header: PollHeader.}: cshort

# One stack-local family-sized destination; padding and IPv6 flow/scope fields start at zero.
proc address(ipv6: bool, port: uint16): Sockaddr_storage =
  result = default(Sockaddr_storage)
  if ipv6:
    # ::1 is the controlled-topology IPv6 destination used by the original proof.
    let a = cast[ptr Address6](addr result)
    a.sin6_family = TSa_Family(ord(nativesocket.AF_INET6))
    a.sin6_port = networkPort(port)
    a.sin6_addr.s6_addr[15] = 1
    when defined(macosx):
      # BSD requires the actual family-specific sockaddr byte length.
      a.sin6_len = uint8(sizeof(Address6))
  else:
    # Preserve IPv4 loopback and its network-order address exactly.
    let a = cast[ptr Sockaddr_in](addr result)
    a.sin_family = TSa_Family(ord(nativesocket.AF_INET))
    a.sin_port = networkPort(port)
    a.sin_addr.s_addr = networkAddress(0x7f000001'u32)
    when defined(macosx):
      # BSD sockaddr_in exposes its length through the public POSIX binding.
      a.sin_len = uint8(sizeof(Sockaddr_in))

# Use the actual family-specific structure extent for every address syscall.
proc addressSize(ipv6: bool): SockLen =
  SockLen(if ipv6: sizeof(Address6) else: sizeof(Sockaddr_in))

proc newDispatcher*(): Dispatcher =
  ## Construct empty dispatcher metadata; it never owns or closes registered sockets.
  Dispatcher(descriptors: default(array[2, cint]), count: 0, closed: false)

proc close*(dispatcher: Dispatcher) =
  ## Closing shared metadata is idempotent; subsequent waits cannot poll reused descriptors.
  dispatcher.closed = true
  dispatcher.count = 0

proc port*(endpoint: UdpEndpoint): uint16 =
  ## Return the copied assigned port without exporting a mutable native address.
  endpoint.portValue
proc descriptor*(endpoint: UdpEndpoint): cint =
  ## Readiness routing compares copied descriptor identities only during the same synchronous dispatch.
  endpoint.descriptor
proc isOpen*(endpoint: UdpEndpoint): bool =
  ## Observe whether this endpoint currently owns an OS descriptor.
  endpoint.opened

# Remove an exact descriptor before close; no endpoint pointer is retained by the dispatcher.
proc retire(dispatcher: Dispatcher, fd: cint) =
  for i in 0..<dispatcher.count:
    # Compaction keeps a retired descriptor out of every future synchronous wait.
    if dispatcher.descriptors[i] == fd:
      dec dispatcher.count
      dispatcher.descriptors[i] = dispatcher.descriptors[dispatcher.count]
      return

# A descriptor has exactly one endpoint owner; explicit moves are allowed, copies are not.
proc `=copy`*(destination: var UdpEndpoint, source: UdpEndpoint) {.error: "UdpEndpoint owns one descriptor".}

proc `=destroy`*(endpoint: UdpEndpoint) =
  ## Scope retirement releases registration first and then the OS resource, including failed setup paths.
  if endpoint.opened:
    let dispatcher = endpoint.registration
    if dispatcher != nil: retire(dispatcher, endpoint.descriptor) # Metadata cannot outlive the socket identity.
    discard posix.close(endpoint.descriptor)
  # A custom destructor must also release its owned ARC field, including already-closed defaults.
  `=destroy`(endpoint.registration)

proc unregister*(dispatcher: Dispatcher, endpoint: var UdpEndpoint) =
  ## Repeated unregister is safe and cannot remove another dispatcher's endpoint.
  let active = endpoint.registration
  if active != nil and active == dispatcher:
    retire(dispatcher, endpoint.descriptor)
    endpoint.registration = nil

proc register*(dispatcher: Dispatcher, endpoint: var UdpEndpoint): bool =
  ## Register one live descriptor once, rejecting exhausted/closed dispatchers without changing them.
  if endpoint.registration != nil: return false # One endpoint cannot belong to two dispatchers.
  if dispatcher.closed or not endpoint.opened or dispatcher.count == 2: return false
  # Duplicate registration cannot consume a second slot or route an event twice.
  for i in 0..<dispatcher.count:
    if dispatcher.descriptors[i] == endpoint.descriptor: return false
  dispatcher.descriptors[dispatcher.count] = endpoint.descriptor
  inc dispatcher.count
  endpoint.registration = dispatcher
  true

proc close*(endpoint: var UdpEndpoint) =
  ## Explicit retirement is ordered by the enclosing transport: unregister, then close the endpoint.
  if endpoint.opened:
    let dispatcher = endpoint.registration
    if dispatcher != nil: dispatcher.unregister(endpoint) # Explicit close shares destructor ordering.
    # Do not retry close after EINTR: the OS may already have recycled the descriptor number.
    discard posix.close(endpoint.descriptor)
    endpoint.opened = false
    endpoint.portValue = 0

proc open*(endpoint: var UdpEndpoint, ipv6: bool, port: uint16): bool =
  ## Open/bind one nonblocking UDP endpoint; every failed setup path releases the newly created descriptor.
  if endpoint.opened: return false # Never overwrite a live resource.
  let fd = socket(cint(ord(if ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET)),
      cint(ord(nativesocket.SOCK_DGRAM)), cint(ord(nativesocket.IPPROTO_UDP)))
  if fd < 0: return false # No descriptor was acquired.
  endpoint = UdpEndpoint(descriptor: fd, opened: true, ipv6: ipv6, portValue: 0, registration: nil)
  let flags = fcntl(fd, F_GETFL)
  let descriptorFlags = fcntl(fd, GetFdFlags)
  # Preserve existing flags, make I/O nonblocking and prevent descriptor inheritance across exec.
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFdFlags, descriptorFlags or CloseExec) < 0:
    close(endpoint)
    return false
  var local = address(ipv6, port)
  var size = addressSize(ipv6)
  if bindSocket(fd, addr local, size) != 0 or socketName(fd, addr local, addr size) != 0:
    # A bind/name-query failure has exactly the same descriptor release owner.
    close(endpoint)
    return false
  endpoint.portValue = hostPort(if ipv6: cast[ptr Address6](addr local).sin6_port else:
      cast[ptr Sockaddr_in](addr local).sin_port)
  true

proc wait*(dispatcher: Dispatcher, maximumMs: int, ready: var openArray[Ready]): int =
  ## Copy readiness for all registrations or fail before polling if the caller cannot hold every result.
  if dispatcher.closed or ready.len < dispatcher.count: return -1
  var entries = default(array[2, PollEntry])
  # Each call rebuilds registrations; retired descriptors cannot remain queued in kernel metadata.
  for i in 0..<dispatcher.count:
    entries[i].fd = dispatcher.descriptors[i]
    entries[i].events = PollRead
  let count = poll(addr entries[0], culong(dispatcher.count), cint(clamp(maximumMs, 0, 10)))
  if count < 0:
    # An interrupt yields to the caller's timers; persistent poll errors fail this dispatcher iteration.
    return if osLastError().int == EINTR.int: 0 else: -1
  result = 0
  for i in 0..<dispatcher.count:
    # Return errors as explicit events rather than reading a descriptor that poll rejected.
    if entries[i].revents != 0:
      ready[result] = Ready(descriptor: entries[i].fd,
          failed: (entries[i].revents and (PollError or PollHangup or PollInvalid)) != 0)
      inc result

proc send*(endpoint: UdpEndpoint, data: pointer, length: int, port: uint16): int =
  ## Send one complete borrowed datagram; -2 means retryable, -1 means failed/invalid input.
  if not endpoint.opened or length < 0 or length > 2048: return -1
  var destination = address(endpoint.ipv6, port)
  let sent = sendTo(endpoint.descriptor, data, csize_t(length), 0, addr destination, addressSize(endpoint.ipv6))
  if sent < 0:
    # Preserve the existing retry policy for would-block and interrupted datagram sends.
    return if osLastError().int in [EAGAIN.int, EWOULDBLOCK.int, EINTR.int]: -2 else: -1
  if sent != length: return -1 # Partial datagrams cannot count as delivered packets.
  sent

proc receive*(endpoint: UdpEndpoint, buffer: var openArray[byte], sourcePort: var uint16): int =
  ## Receive one copied datagram; -2 means retryable, -1 means error, zero includes rejected source scope.
  sourcePort = 0
  if not endpoint.opened or buffer.len == 0: return -1
  var source = default(Sockaddr_storage)
  var size = addressSize(endpoint.ipv6)
  let count = receiveFrom(endpoint.descriptor, addr buffer[0], csize_t(buffer.len), 0, addr source, addr size)
  if count < 0:
    # No pending read borrows this buffer after a would-block/interrupt result.
    return if osLastError().int in [EAGAIN.int, EWOULDBLOCK.int, EINTR.int]: -2 else: -1
  if size != addressSize(endpoint.ipv6): return 0 # Never inspect an incomplete source address.
  if endpoint.ipv6:
    let a = cast[ptr Address6](addr source)
    if a.sin6_family != TSa_Family(ord(nativesocket.AF_INET6)): return 0
    # Check all IPv6 bytes; a non-loopback address cannot be attributed to the loopback proof.
    for i in 0..<15:
      if a.sin6_addr.s6_addr[i] != 0: return 0
    if a.sin6_addr.s6_addr[15] != 1: return 0
    sourcePort = hostPort(a.sin6_port)
  else:
    # Match the complete IPv4 loopback address before handing its port to LSQUIC.
    let a = cast[ptr Sockaddr_in](addr source)
    if a.sin_family != TSa_Family(ord(nativesocket.AF_INET)) or
        a.sin_addr.s_addr != networkAddress(0x7f000001'u32): return 0
    sourcePort = hostPort(a.sin_port)
  count

proc retirementSelfTest*(ipv6: bool) =
  ## Replay the original idle/ready retirement matrix on both supported controlled-topology families.
  let dispatcher = newDispatcher()
  defer: dispatcher.close()
  # Reusing one dispatcher catches stale registrations after descriptors are closed/recycled.
  for iteration in 0..<256:
    var endpoint = default(UdpEndpoint)
    assert endpoint.open(ipv6, 0)
    assert endpoint.isOpen and endpoint.port != 0
    assert dispatcher.register(endpoint)
    assert not dispatcher.register(endpoint)
    var ready = default(array[2, Ready])
    var payload = [99'u8]
    var source: uint16 = 0
    assert endpoint.receive(payload, source) == -2 and source == 0
    # Alternating cases retire either a quiet descriptor or one with unread queued data.
    if iteration mod 2 == 0:
      assert endpoint.send(addr payload[0], 1, endpoint.port) == 1
      assert dispatcher.wait(10, ready) == 1
      assert ready[0].descriptor == endpoint.descriptor and not ready[0].failed
    else:
      # Idle waits must not manufacture readiness for an empty nonblocking UDP socket.
      assert dispatcher.wait(0, ready) == 0
    dispatcher.unregister(endpoint)
    endpoint.close()
    endpoint.close()
    assert not endpoint.isOpen and endpoint.port == 0
    assert dispatcher.wait(0, ready) == 0
  echo "UDP_RETIREMENTS ipv6=", ipv6, " rounds=256"

