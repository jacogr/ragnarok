# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed endpoint identities, validator metadata, real UDP source tuples and addressed QUIC TLS.
import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/quic/[address, io, transport]
import ../../../src/jamnp-s/[protocol, endpoints]

type Party = object ## Stable callback storage retires only after both native engines close.
  transport: Transport
  server: bool
  expected: array[32, byte]
proc `=copy`(destination: var Party, source: Party) {.error.}
  ## A copied endpoint cannot retain another owner's callback address.
proc `=dup`(source: Party): Party {.error.}
  ## Implicit duplication is forbidden along with assignment.
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Incoming peers discover valid key/SAN identities; the dialer still pins the server.
  let party = cast[ptr Party](user)
  if party.server: return cint(validPeer(cast[ptr byte](der), length, []))
  cint(validPeer(cast[ptr byte](der), length, party.expected))
proc event(user: pointer, stream: NativeStream, kind: cint) {.cdecl, raises: [].} =
  ## Address routing is tested independently of application messages.
  if kind == 0: streamAbort(stream)
proc parsed(text: string): NetworkAddress =
  ## Test literals have explicit families and exact bytes; no DNS/environment route is consulted.
  result = default(NetworkAddress)
  assert parseNetworkAddress(text, result)
proc key(path: string): array[32, byte] {.raises.} =
  ## Fixtures bind exact raw Ed25519 keys independently from endpoint data.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])

proc addressedTls(ipv6: bool) {.raises.} =
  ## A wildcard listener routes replies using the actual source tuple, including its complete IP.
  var server = Party(server: true)
  var client = Party(server: false)
  client.expected = key(getEnv("RAGNAROK_TEST_PEER_A"))
  let wildcard = parsed(if ipv6: "::" else: "0.0.0.0")
  var source = loopbackAddress(ipv6)
  when defined(linux):
    if not ipv6: source = parsed("127.0.0.2") # Linux routes all127/8; reconstructing127.0.0.1 would lose this client.
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport) # Both borrowed Party pointers remain stable through final callbacks.
  assert openTransport(server.transport, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, verify, event,
        localAddress = wildcard)
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr client, verify, event,
        localAddress = source)
  assert not connectTransport(client.transport, networkEndpoint(wildcard, localPort(
      server.transport)))
  assert connectTransport(client.transport, networkEndpoint(loopbackAddress(ipv6), localPort(
      server.transport)))
  let deadline = getMonoTime() + initDuration(seconds = 2)
  var connected = false
  while getMonoTime() < deadline:
    assert pollTransport(server.transport, 0) and pollTransport(client.transport, 0)
    if transportStatus(client.transport) == 1 and authenticatedConnections(server.transport) > 0:
      connected = true
      break # Real mutual TLS requires replies to return to the same complete client tuple.
  assert connected

proc datagrams(ipv6: bool) =
  ## Explicit address binding supports wildcard listeners and returns copied source IP plus port.
  var receiver, sender = default(UdpEndpoint)
  defer:
    receiver.close()
    sender.close() # Callback-free UDP ownership still retires every descriptor.
  let wildcard = parsed(if ipv6: "::" else: "0.0.0.0")
  assert receiver.open(networkEndpoint(wildcard, 0))
  var source = loopbackAddress(ipv6)
  when defined(linux):
    if not ipv6: source = parsed("127.0.0.2") # A valid non-default source must survive receive filtering.
  assert sender.open(networkEndpoint(source, 0))
  var payload = [17'u8, 28, 39]
  assert sender.send(addr payload[0], payload.len, networkEndpoint(loopbackAddress(ipv6),
      receiver.port)) == payload.len
  let deadline = getMonoTime() + initDuration(seconds = 2)
  var received = false
  while getMonoTime() < deadline:
    var bytes = default(array[8, byte])
    var peer = default(NetworkEndpoint)
    let count = receiver.receive(bytes, peer)
    if count > 0:
      assert count == payload.len and bytes[0] == 17 and bytes[2] == 39
      assert peer.valid and peer.address == source and peer.port == sender.port
      received = true
      break # Source identity is verified independently from the payload's byte count.
  assert received
  var stale = networkEndpoint(source, sender.port)
  var bytes = default(array[8, byte])
  assert receiver.receive(bytes, stale) == -2 and not stale.valid # Would-block cannot replay the preceding source.

when defined(linux):
  proc samePortSources() =
    ## Distinct source IPs sharing one source port must remain distinct after UDP reception.
    var receiver, first, second = default(UdpEndpoint)
    defer:
      receiver.close(); first.close(); second.close() # Every bounded fixture descriptor has one retirement owner.
    let firstIp = parsed("127.0.0.2")
    let secondIp = parsed("127.0.0.3")
    assert receiver.open(networkEndpoint(parsed("0.0.0.0"), 0))
    assert first.open(networkEndpoint(firstIp, 0))
    assert second.open(networkEndpoint(secondIp, first.port))
    var one = [1'u8]
    var two = [2'u8]
    let target = networkEndpoint(loopbackAddress(false), receiver.port)
    assert first.send(addr one[0], 1, target) == 1
    assert second.send(addr two[0], 1, target) == 1
    var mask = 0
    let deadline = getMonoTime() + initDuration(seconds = 2)
    while getMonoTime() < deadline and mask != 3:
      var payload = default(array[8, byte])
      var source = default(NetworkEndpoint)
      let count = receiver.receive(payload, source)
      if count > 0:
        assert count == 1 and source.port == first.port
        if payload[0] == 1:
          assert source.address == firstIp
          mask = mask or 1
        else:
          assert payload[0] == 2 and source.address == secondIp
          mask = mask or 2
    assert mask == 3

proc main() {.raises.} =
  ## Roundtrip numeric forms, preserve family identity and read metadata's port in little-endian order.
  for text in ["::1", "2001:db8:1234:5678::9", "::ffff:192.0.2.5", "192.0.2.5", "0.0.0.0"]:
    let address = parsed(text)
    assert parsed($address) == address
  var invalid = parsed("::1")
  for text in ["", "localhost", "::1\0suffix", " ::1", "300.1.2.3", "2001:db8::g"]:
    assert not parseNetworkAddress(text, invalid) and not invalid.valid
  let ip = parsed("2001:db8::1234")
  let endpoint = networkEndpoint(ip, 0x1234)
  var closed = default(Transport)
  assert not connectTransport(closed, endpoint)
  let empty = default(EndpointResult)
  assert empty.error == EndpointError.Uninitialized
  var metadata = newSeq[byte](128)
  let raw = ip.bytes
  for index in 0..<16: metadata[index] = raw[index]
  metadata[16] = 0x34; metadata[17] = 0x12
  assert validatorEndpoint(metadata).value == endpoint
  for length in 0..<18:
    assert validatorEndpoint(metadata.toOpenArray(0, length-1)).error == EndpointError.Truncated
  metadata[16] = 0; metadata[17] = 0
  assert validatorEndpoint(metadata).error == EndpointError.Unavailable
  when defined(linux): samePortSources() # Equal ports never replace source-IP identity.
  for ipv6 in [false, true]:
    datagrams(ipv6)
    addressedTls(ipv6) # Exercise both actual native socket families through the same complete-address ABI.

try:
  main()
except:
  quit 2 # Setup/environment errors are never successful network evidence.
echo "JAMNP-S full endpoints, validator metadata, UDP source identity and addressed TLS passed"
