# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated certificate/ALPN correlation stays exact across concurrent same-key connections.

import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/quic/transport
import ../../../src/jamnp-s/[protocol, alpn]

type Party = object ## Native callbacks borrow this stable address until explicit engine closure.
  transport: Transport
  server, opened, allowBuilder, invalid: bool
  pin: array[32, byte]
  live, proposed: array[2, bool]
  admitted, closed, baseQueries, builderQueries, refused: int

proc `=copy`(destination: var Party, source: Party) {.error.}
  ## A copy cannot transfer the foreign callback address or its retirement authority.

proc `=dup`(source: Party): Party {.error.}
  ## Last-use duplication is prohibited along with assignment.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Server checks complete certificate/SAN validity; clients pin the listener's fixture identity.
  let owner = cast[ptr Party](user)
  if owner.server: return cint(validPeer(cast[ptr byte](der), length, []))
  cint(validPeer(cast[ptr byte](der), length, owner.pin))

proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## No application exchange is required for this admission boundary.
  if event == 0: streamAbort(handle)

proc matches(bytes: ptr ConstByte, length: csize_t, expected: string): bool =
  ## Bound every borrowed byte comparison before reading the synchronous native span.
  if bytes == nil or length != csize_t(expected.len): return false
  let raw = cast[ptr UncheckedArray[byte]](bytes)
  for index in 0..<expected.len:
    if raw[index] != byte(expected[index]): return false # Exact ALPN, no suffix/prefix guessing.
  true

proc admit(user: pointer, slot: cuint, der: ptr ConstByte, length: csize_t,
    protocol: ptr ConstByte, protocolLength: csize_t): cint {.cdecl, raises: [].} =
  ## A builder request has an independent policy decision despite presenting the same client key.
  let owner = cast[ptr Party](user)
  if slot >= 2 or der == nil or length == 0 or not validPeer(cast[ptr byte](der), length, []):
    owner.invalid = true
    return 0 # Incomplete primitive facts never become policy success.
  let index = int(slot)
  if owner.live[index] or owner.proposed[index]: owner.invalid = true; return 0
  if matches(protocol, protocolLength, "jamnp-s/1/00000000/builder"):
    inc owner.builderQueries
    if not owner.allowBuilder:
      inc owner.refused
      return 0 # Policy refusal must not retain the offered native slot.
  elif matches(protocol, protocolLength, "jamnp-s/1/00000000"):
    inc owner.baseQueries
  else:
    owner.invalid = true
    return 0 # The accepted protocol must be one of the actual configured alternatives.
  owner.proposed[index] = true
  1

proc peer(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  ## Acceptance must follow a successful policy decision for this exact retained slot.
  let owner = cast[ptr Party](user)
  if slot >= 2: owner.invalid = true; return
  let index = int(slot)
  if event == PeerAccepted:
    if owner.live[index] or not owner.proposed[index]: owner.invalid = true; return
    owner.proposed[index] = false
    owner.live[index] = true
    inc owner.admitted
  elif event == PeerClosed:
    if not owner.live[index]: owner.invalid = true; return
    owner.live[index] = false
    inc owner.closed
  else: owner.invalid = true # No other event grants or retires an admission.

proc key(path: string): array[32, byte] {.raises.} =
  ## Copy exact generated fixture key bytes for the independent client pin.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])

proc connect(client: var Party, port: uint16, builder, ipv6: bool) {.raises.} =
  ## All clients deliberately use one certificate; negotiated role remains per connection.
  client.pin = key(getEnv("RAGNAROK_TEST_PEER_A"))
  let protocol = if builder: "jamnp-s/1/00000000/builder" else: "jamnp-s/1/00000000"
  assert client.transport.openTransport(false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), protocol, addr client, verify, stream, ipv6 = ipv6)
  client.opened = true
  assert not client.transport.admitPeers(admit) # Outgoing endpoints cannot install incoming policy.
  assert client.transport.connectTransport(port)

proc pump(server: var Party, clients: var array[4, Party], admitted, refused, closed: int) =
  ## Wait for actual server observations, not the client's earlier TLS-success flag.
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0)
    for index in 0..<clients.len:
      if clients[index].opened: assert clients[index].transport.pollTransport(0)
    assert not server.invalid
    if server.admitted == admitted and server.refused == refused and server.closed == closed: return
  assert false, "admission observation timeout: accepted=" & $server.admitted & " refused=" &
      $server.refused & " closed=" & $server.closed

proc scenario(ipv6: bool) {.raises.} =
  ## Same-key base/builder overlap, rejection, later permission and a genuine slot reuse.
  var server = Party(server: true)
  var clients = default(array[4, Party])
  defer:
    for index in 0..<clients.len: clients[index].transport.closeTransport()
    server.transport.closeTransport() # SSL registry entries retire while the Party is still alive.
  assert server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, verify, stream,
    multi = true, ipv6 = ipv6, acceptedAlpns = serverAlpns("jamnp-s/1/00000000"), incomingPeers = 2)
  assert server.transport.admitPeers(admit)
  assert not server.transport.admitPeers(admit) # Replacement must retain the original policy.
  assert server.transport.observePeers(peer)
  connect(clients[0], localPort(server.transport), false, ipv6)
  connect(clients[1], localPort(server.transport), true, ipv6)
  pump(server, clients, 1, 1, 0)
  assert server.baseQueries == 1 and server.builderQueries == 1
  assert peerMetric(server.transport, 0) == 1
  # More refusals than the66-entry TLS registry prove aborted SSL entries are reusable.
  for cycle in 0..<72:
    clients[1].transport.closeTransport()
    clients[1].opened = false
    connect(clients[1], localPort(server.transport), true, ipv6)
    pump(server, clients, 1, cycle+2, 0)
    assert peerMetric(server.transport, 0) == 1 # Refused identities never consume authenticated capacity.
  server.allowBuilder = true
  connect(clients[2], localPort(server.transport), true, ipv6)
  pump(server, clients, 2, 73, 0)
  assert peerMetric(server.transport, 0) == 2
  clients[0].transport.disconnectTransport()
  pump(server, clients, 2, 73, 1)
  clients[0].transport.closeTransport()
  clients[0].opened = false # Descriptor reuse follows its actual final native retirement.
  connect(clients[3], localPort(server.transport), false, ipv6)
  pump(server, clients, 3, 73, 1)
  assert server.baseQueries == 2 and server.builderQueries == 74
  assert peerMetric(server.transport, 0) == 2 and not server.invalid

proc startup() {.raises.} =
  ## Late first registration refuses atomically; the same retired owner can be reopened and configured.
  var owner = Party(server: true)
  defer: owner.transport.closeTransport()
  for cycle in 0..<2:
    assert owner.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
      getEnv("RAGNAROK_TEST_KEY"), "admission/startup", addr owner, verify, stream)
    if cycle == 0:
      assert owner.transport.pollTransport(0)
      assert not owner.transport.admitPeers(admit) # Native processing freezes startup policy.
    else:
      assert owner.transport.admitPeers(admit) # Failed/retired setup retained no stale callback.
    owner.transport.closeTransport()

try:
  startup()
  scenario(false)
  scenario(true)
except:
  quit 2 # Fixture IO/setup failure never counts as passing TLS admission.
echo "quic admission: authenticated same-key ALPN policy, refusal and slot reuse passed"
