# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-threaded bounded POSIX readiness and loopback UDP for the maintained QUIC adapter. No
## pending syscall retains buffers; unregister precedes descriptor close and descriptor reuse.
##
## Exposes dispatcher and UDP endpoint ownership, descriptor registration, bounded
## wait/send/receive and explicit close operations.

import std/[assertions, oserrors, nativesocket, syncio]
import std/posix/posix
import ./address
export address

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
    opened, ipv6, loopbackOnly: bool
    portValue: uint16
    registration: nil Dispatcher
  Ready* = object ## One copied readiness event; no pointer into poll's temporary storage escapes.
    descriptor*: cint
    failed*: bool

proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: SocketHeader.}
  ## Socket creation/configuration calls bind public OS headers, never compiler/runtime internals.

proc bindSocket(fd: cint, address: pointer, length: SockLen): cint {.importc: "bind",
    header: SocketHeader.}
  ## Addresses are borrowed synchronously and use the family-specific byte extent.

proc socketName(fd: cint, address: pointer, length: ptr SockLen): cint {.importc: "getsockname",
    header: SocketHeader.}
  ## Query the actual assigned port after a successful ephemeral bind.

proc sendTo(fd: cint, data: pointer, length: csize_t, flags: cint, address: pointer,
    addressLength: SockLen): int {.importc: "sendto", header: SocketHeader.}
  ## Datagram syscalls never retain caller/native-library buffers after returning.

proc receiveFrom(fd: cint, data: pointer, length: csize_t, flags: cint, address: pointer,
    addressLength: ptr SockLen): int {.importc: "recvfrom", header: SocketHeader.}
  ## One nonblocking datagram read, with a copied source address for native-language scope validation.

proc hostPort(port: uint16): uint16 {.importc: "ntohs", header: AddressHeader.}
  ## Native byte-order helpers use the public platform declarations.

proc networkPort(port: uint16): uint16 {.importc: "htons", header: AddressHeader.}
  ## Convert ports for either loopback family.

proc networkOrder(address: uint32): uint32 {.importc: "htonl", header: AddressHeader.}
  ## IPv4 address conversion remains independent of host endianness.

proc poll(entries: ptr PollEntry, count: culong, timeout: cint): cint {.importc: "poll",
    header: PollHeader.}
  ## A bounded readiness wait borrows at most two entries and never creates worker threads.

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

proc socketAddress(target: NetworkEndpoint): Sockaddr_storage =
  ## Convert one complete tuple, preserving every IP byte and the supplied port.
  result = default(Sockaddr_storage)
  let ip = target.address
  if ip.ipv6:
    let native = cast[ptr Address6](addr result)
    native.sin6_family = TSa_Family(ord(nativesocket.AF_INET6))
    native.sin6_port = networkPort(target.port)
    let bytes = ip.bytes
    for index in 0..<16: native.sin6_addr.s6_addr[index] = bytes[index]
    when defined(macosx): native.sin6_len = uint8(sizeof(Address6)) # BSD records carry their own exact extent.
  else:
    let native = cast[ptr Sockaddr_in](addr result)
    native.sin_family = TSa_Family(ord(nativesocket.AF_INET))
    native.sin_port = networkPort(target.port)
    let bytes = ip.ipv4Bytes
    var integer = 0'u32
    for octet in bytes: integer = (integer shl 8) or uint32(octet) # Four octets bound every shift.
    native.sin_addr.s_addr = networkOrder(integer)
    when defined(macosx): native.sin_len = uint8(sizeof(Sockaddr_in)) # BSD IPv4 uses its family-specific length.

proc socketAddress(ipv6: bool, port: uint16): Sockaddr_storage =
  ## The legacy entry point explicitly retains its controlled loopback destination.
  socketAddress(networkEndpoint(loopbackAddress(ipv6), port))

proc addressSize(ipv6: bool): SockLen =
  ## Use the actual family-specific structure extent for every address syscall.
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

proc retire(dispatcher: Dispatcher, fd: cint) =
  ## Remove an exact descriptor before close; no endpoint pointer is retained by the dispatcher.
  for i in 0..<dispatcher.count:
    # Compaction keeps a retired descriptor out of every future synchronous wait.
    if dispatcher.descriptors[i] == fd:
      dec dispatcher.count
      dispatcher.descriptors[i] = dispatcher.descriptors[dispatcher.count]
      return

proc `=copy`*(destination: var UdpEndpoint, source: UdpEndpoint) {.error: "UdpEndpoint owns one descriptor".}
  ## A descriptor has exactly one endpoint owner; explicit moves are allowed, copies are not.

proc `=dup`*(source: UdpEndpoint): UdpEndpoint {.error.}
  ## Implicit duplication cannot duplicate native retirement authority.

proc `=wasMoved`*(endpoint: var UdpEndpoint) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  endpoint.opened = false
  endpoint.descriptor = -1
  endpoint.ipv6 = false
  endpoint.loopbackOnly = false
  endpoint.portValue = 0
  `=wasMoved`(endpoint.registration)

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

proc open*(endpoint: var UdpEndpoint, binding: NetworkEndpoint): bool =
  ## Open/bind one nonblocking UDP endpoint; every failed setup path releases the newly created descriptor.
  if endpoint.opened or not binding.valid: return false # Never overwrite a live resource.
  let ipv6 = binding.address.ipv6
  let fd = socket(cint(ord(if ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET)),
      cint(ord(nativesocket.SOCK_DGRAM)), cint(ord(nativesocket.IPPROTO_UDP)))
  if fd < 0: return false # No descriptor was acquired.
  endpoint = UdpEndpoint(descriptor: fd, opened: true, ipv6: ipv6, loopbackOnly: false,
      portValue: 0, registration: nil)
  let flags = fcntl(fd, F_GETFL)
  let descriptorFlags = fcntl(fd, GetFdFlags)
  # Preserve existing flags, make I/O nonblocking and prevent descriptor inheritance across exec.
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFdFlags, descriptorFlags or CloseExec) < 0:
    close(endpoint)
    return false
  var local = socketAddress(binding)
  var size = addressSize(ipv6)
  if bindSocket(fd, addr local, size) != 0 or socketName(fd, addr local, addr size) != 0:
    # A bind/name-query failure has exactly the same descriptor release owner.
    close(endpoint)
    return false
  endpoint.portValue = hostPort(if ipv6: cast[ptr Address6](addr local).sin6_port else:
      cast[ptr Sockaddr_in](addr local).sin_port)
  true

proc open*(endpoint: var UdpEndpoint, ipv6: bool, port: uint16): bool =
  ## Compatibility callers retain both loopback binding and exact source filtering.
  result = endpoint.open(networkEndpoint(loopbackAddress(ipv6), port))
  if result: endpoint.loopbackOnly = true

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

proc send*(endpoint: UdpEndpoint, data: pointer, length: int, target: NetworkEndpoint): int =
  ## Send one complete borrowed datagram; -2 means retryable, -1 means failed/invalid input.
  if not endpoint.opened or not target.valid or length < 0 or length > 2048: return -1
  if target.address.ipv6 != endpoint.ipv6: return -1 # Families never change through a port-only alias.
  var destination = socketAddress(target)
  let sent = sendTo(endpoint.descriptor, data, csize_t(length), 0, addr destination, addressSize(endpoint.ipv6))
  if sent < 0:
    # Preserve the existing retry policy for would-block and interrupted datagram sends.
    return if osLastError().int in [EAGAIN.int, EWOULDBLOCK.int, EINTR.int]: -2 else: -1
  if sent != length: return -1 # Partial datagrams cannot count as delivered packets.
  sent

proc send*(endpoint: UdpEndpoint, data: pointer, length: int, port: uint16): int =
  ## Legacy proof sends retain the original exact loopback target.
  endpoint.send(data, length, networkEndpoint(loopbackAddress(endpoint.ipv6), port))

proc receive*(endpoint: UdpEndpoint, buffer: var openArray[byte],
    remote: var NetworkEndpoint): int =
  ## Copy the whole source tuple before retiring syscall storage; errors retain no previous source.
  remote = default(NetworkEndpoint)
  if not endpoint.opened or buffer.len == 0: return -1
  var source = default(Sockaddr_storage)
  var size = addressSize(endpoint.ipv6)
  let count = receiveFrom(endpoint.descriptor, addr buffer[0], csize_t(buffer.len), 0, addr source, addr size)
  if count < 0:
    return if osLastError().int in [EAGAIN.int, EWOULDBLOCK.int,
        EINTR.int]: -2 else: -1 # Retryable OS outcomes preserve no borrow.
  if size != addressSize(endpoint.ipv6): return 0
  var ip = default(NetworkAddress)
  var port = 0'u16
  if endpoint.ipv6:
    let native = cast[ptr Address6](addr source)
    if native.sin6_family != TSa_Family(ord(nativesocket.AF_INET6)): return 0
    var bytes = default(array[16, byte])
    for index in 0..<16: bytes[index] = native.sin6_addr.s6_addr[
        index] # Family/extent prove the entire fixed borrow.
    ip = ipv6Address(bytes)
    port = hostPort(native.sin6_port)
  else:
    let native = cast[ptr Sockaddr_in](addr source)
    if native.sin_family != TSa_Family(ord(nativesocket.AF_INET)): return 0
    let integer = networkOrder(native.sin_addr.s_addr) # Network/host swapping is symmetric for this fixed word.
    var bytes = default(array[4, byte])
    for index in 0..<4: bytes[index] = byte((integer shr (8*(3-index))) and 255)
    ip = ipv4Address(bytes)
    port = hostPort(native.sin_port)
  if endpoint.loopbackOnly and not ip.loopback: return 0 # Old proof callers retain their documented receive scope.
  remote = networkEndpoint(ip, port)
  count

proc receive*(endpoint: UdpEndpoint, buffer: var openArray[byte], sourcePort: var uint16): int =
  ## Existing callers may intentionally discard IP data only after complete source validation.
  sourcePort = 0
  var remote = default(NetworkEndpoint)
  result = endpoint.receive(buffer, remote)
  if remote.valid: sourcePort = remote.port

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

