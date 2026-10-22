# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared real loopback WebSocket controls retain bounded polling and explicit native descriptor ownership.
import std/[assertions, strutils, nativesocket]
import std/posix/posix
import ../../src/rpc/server

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bound local polling pauses through the host SDK.
proc openSocket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Create a real native loopback descriptor for tests.
proc bindPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
  ## Bind explicit initialized native addresses.
proc socketName(fd: cint, address: pointer, length: ptr SockLen): cint {.importc: "getsockname",
    header: "<sys/socket.h>".}
  ## Read the actual ephemeral port assigned by the kernel.
proc connectPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## Connect a client only to the selected local endpoint.
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
  ## Convert the configured port to network byte order.
proc hostPort(port: uint16): uint16 {.importc: "ntohs", header: "<netinet/in.h>".}
  ## Convert the kernel-selected port to host byte order.
proc ipv4(text: cstring): uint32 {.importc: "inet_addr", header: "<arpa/inet.h>".}
  ## Use the SDK IPv4 parser for fixed loopback text.
proc sendBytes(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Send only the initialized test frame extent.
proc receive(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Receive into bounded explicitly initialized test storage.

proc address(port: uint16): Sockaddr_in =
  ## Native addresses use the real OS-selected loopback port and explicit initialization on every platform.
  result = default(Sockaddr_in)
  result.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  result.sin_port = networkPort(port)
  result.sin_addr.s_addr = ipv4("127.0.0.1")
  when defined(macosx):
    result.sin_len = uint8(sizeof(result)) # Darwin requires the native address extent.

proc client*(port: uint16): cint =
  ## Connect only to this local listener, then make all test reads nonblocking with bounded polling.
  let fd = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert fd >= 0
  var destination = address(port)
  assert connectPort(fd, addr destination, SockLen(sizeof(destination))) == 0
  let flags = fcntl(fd, F_GETFL, 0)
  assert flags >= 0 and fcntl(fd, F_SETFL, flags or O_NONBLOCK) == 0
  fd

proc sendText*(peer: cint, text: string, masked = true) =
  ## Send one bounded independently masked short/medium client frame, or a literal upgrade header.
  var packet = text
  if masked:
    assert text.len <= 65535
    if text.len < 126:
      packet = "\x81" & $char(128 or text.len) # Canonical short frames retain their existing encoding.
    else:
      packet = "\x81\xfe" & $char(text.len shr 8) & $char(text.len and 255) # Network-order medium extent.
    packet.add("abcd")
    for index, octet in text: packet.add(char(ord(octet) xor ord("abcd"[index mod 4])))
  assert sendBytes(peer, packet.toCString(), csize_t(packet.len), 0) == packet.len

proc readPacket*(rpc: var Server, peer: cint, pending: var string, upgrade = false): string =
  ## Independently decode a complete bounded server frame; retain coalesced suffixes across dispatcher turns.
  for attempt in 0..<200:
    if upgrade:
      let ending = pending.find("\r\n\r\n")
      if ending >= 0:
        result = pending.substr(0, ending + 3)
        pending = pending.substr(ending + 4)
        return # Header consumption retains any subsequent frame bytes.
    elif pending.len >= 2:
      assert ord(pending[0]) == 129 and (ord(pending[1]) and 128) == 0
      var size = ord(pending[1])
      var offset = 2
      if size == 126:
        if pending.len < 4: size = -1 # Wait for both initialized length octets.
        else:
          size = ord(pending[2]) * 256 + ord(pending[3])
          offset = 4
      assert ord(pending[1]) != 127
      if size >= 0 and pending.len >= offset + size:
        result = pending.substr(offset, offset + size - 1)
        pending = pending.substr(offset + size)
        return # One decoded payload never consumes the next notification.
    rpc.tick(0)
    var buffer = default(array[8192, char])
    let count = receive(peer, addr buffer[0], csize_t(buffer.len), 0)
    if count > 0:
      for index in 0..<count: pending.add(buffer[index]) # Only initialized receive bytes enter the bounded test buffer.
      assert pending.len <= 16384
    else:
      assert count < 0 # Unexpected EOF is a test failure, never an empty successful frame.
      discard pauseMicros(1000) # Bound local transport scheduling without an unbounded blocking receive.
  assert false, "RPC packet did not arrive"
  ""

proc reservation*(): tuple[fd: cint, port: uint16] =
  ## Keep an OS-assigned loopback port occupied until the caller deliberately releases it.
  let probe = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert probe >= 0
  var selected = address(0)
  assert bindPort(probe, addr selected, SockLen(sizeof(selected))) == 0
  var size = SockLen(sizeof(selected))
  assert socketName(probe, addr selected, addr size) == 0
  (probe, hostPort(selected.sin_port))

proc assertPortReleased*(port: uint16) =
  ## Prove failed startup released a listener by rebinding its real local port.
  let probe = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert probe >= 0
  defer: discard posix.close(probe)
  var released = address(port)
  assert bindPort(probe, addr released, SockLen(sizeof(released))) == 0, "RPC refusal releases the opened UI listener"
proc upgrade*(rpc: var Server, peer: cint, pending: var string) =
  ## Exercise the real HTTP upgrade before sending masked JSON-RPC requests.
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(rpc, peer, pending, true)
