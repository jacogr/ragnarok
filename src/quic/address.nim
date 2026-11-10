# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied numeric IP endpoints for UDP and QUIC. No DNS lookup or borrowed sockaddr storage
## escapes these values; IPv4 uses a canonical mapped sixteen-byte representation.

import std/nativesocket
import std/posix/posix

type
  NetworkAddress* = object ## Private family prevents a default value from authorizing native address access.
    kind: uint8
    octets: array[16, byte]
  NetworkEndpoint* = object ## One fixed address/port tuple; port zero is valid for a local ephemeral bind.
    host: NetworkAddress
    number: uint16

func valid*(address: NetworkAddress): bool =
  ## Only explicit address constructors provide a native family.
  address.kind == 4 or address.kind == 6

func ipv6*(address: NetworkAddress): bool {.requires: address.valid.} =
  ## IPv4-mapped IPv6 addresses retain their socket-family identity.
  address.kind == 6

func bytes*(address: NetworkAddress): array[16, byte] {.requires: address.valid.} =
  ## Return a fixed copy, never a mutable view into caller or OS storage.
  address.octets

func ipv4Bytes*(address: NetworkAddress): array[4, byte] {.requires: address.valid and
    not address.ipv6.} =
  ## Four network-order octets reconstruct the native IPv4 address without host-order aliasing.
  [address.octets[12], address.octets[13], address.octets[14], address.octets[15]]

func ipv6Address*(octets: array[16, byte]): NetworkAddress =
  ## All sixteen address bytes are data, including unspecified addresses used by listeners.
  NetworkAddress(kind: 6, octets: octets)

func ipv4Address*(octets: array[4, byte]): NetworkAddress =
  ## Normalize IPv4 in fixed storage while retaining the IPv4 socket family.
  result = NetworkAddress(kind: 4)
  result.octets[10] = 255; result.octets[11] = 255
  for index in 0..<4: result.octets[index+12] = octets[index]

func loopbackAddress*(ipv6: bool): NetworkAddress =
  ## Legacy proof APIs explicitly select their original loopback scope.
  if ipv6:
    var octets = default(array[16, byte])
    octets[15] = 1
    return ipv6Address(octets)
  ipv4Address([127'u8, 0, 0, 1])

func unspecified*(address: NetworkAddress): bool {.requires: address.valid.} =
  ## A wildcard is useful for binding, never a concrete remote destination.
  if address.ipv6:
    for octet in address.octets:
      if octet != 0: return false # Any nonzero IPv6 octet excludes the wildcard.
    return true
  address.ipv4Bytes == [0'u8, 0, 0, 0]

func loopback*(address: NetworkAddress): bool {.requires: address.valid.} =
  ## Legacy receive filtering retains the exact original addresses, not all of127/8.
  address == loopbackAddress(address.ipv6)

func `==`*(left, right: NetworkAddress): bool =
  ## Identical bits in different socket families do not silently change routing semantics.
  left.kind == right.kind and left.octets == right.octets

func networkEndpoint*(address: NetworkAddress, port: uint16): NetworkEndpoint {.requires: address.valid.} =
  ## Construct one complete copied native tuple.
  NetworkEndpoint(host: address, number: port)

func valid*(endpoint: NetworkEndpoint): bool =
  ## A default endpoint contains no usable family, even when its numeric fields are zero.
  endpoint.host.valid

func address*(endpoint: NetworkEndpoint): NetworkAddress {.requires: endpoint.valid.} =
  ## Return a fixed address copy, preserving its family.
  endpoint.host

func port*(endpoint: NetworkEndpoint): uint16 {.requires: endpoint.valid.} =
  ## Local zero ports request kernel allocation; remote callers reject zero before dialing.
  endpoint.number

func `==`*(left, right: NetworkEndpoint): bool =
  ## Different IPs on one UDP port remain distinct peer endpoints.
  left.host == right.host and left.number == right.number

proc nativeParse(family: cint, text: cstring, output: pointer): cint {.importc: "inet_pton",
    header: "<arpa/inet.h>".}
  ## The platform parser accepts numeric literals only and borrows both buffers synchronously.

proc nativeText(family: cint, input, output: pointer,
    size: SockLen): cstring {.importc: "inet_ntop", header: "<arpa/inet.h>".}
  ## Native rendering writes into caller-owned fixed storage; no static buffer is retained.

proc parseNetworkAddress*(text: string, output: var NetworkAddress): bool =
  ## Parse bounded numeric IPv4/IPv6 atomically; failure clears an earlier successful value.
  output = default(NetworkAddress)
  if text.len == 0 or text.len > 45: return false
  for character in text:
    if ord(character) <= 32 or ord(character) >= 127: return false # Reject native truncation, whitespace and non-ASCII spelling.
  var terminated = text
  var v6 = default(array[16, byte])
  if nativeParse(cint(ord(nativesocket.AF_INET6)), terminated.toCString(), addr v6[0]) == 1:
    output = ipv6Address(v6)
    return true
  var v4 = default(array[4, byte])
  if nativeParse(cint(ord(nativesocket.AF_INET)), terminated.toCString(), addr v4[0]) == 1:
    output = ipv4Address(v4)
    return true
  false

proc `$`*(address: NetworkAddress): string =
  ## A default address renders empty; valid values never resolve hostnames.
  if not address.valid: return ""
  var octets = address.bytes
  var output = default(array[64, char])
  let offset = if address.ipv6: 0 else: 12
  let family = if address.ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET
  if nativeText(cint(ord(family)), addr octets[offset], addr output[0], SockLen(output.len)) == nil:
    return "" # Native conversion failure cannot expose uninitialized bytes.
  result = ""
  for character in output:
    if character == char(0): break # Only initialized bytes preceding the terminator are copied.
    result.add(character)
