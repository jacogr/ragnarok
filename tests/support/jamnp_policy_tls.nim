# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS witness binds validator reservations to authenticated certificate identity and ALPN.

import std/[assertions, syncio, envvars, monotimes, times]
import ./jamnp_topology_fixture
import ../../src/jamnp-s/[admission, topology, protocol, alpn]
import ../../src/quic/transport
import ../../src/chain/[genesis, provider]
import ../../src/codec/state/safrole

type Party = object ## Stable native callback owner explicitly retires every engine before destruction.
  transport: Transport
  policy: ValidatorAdmission
  pin: array[32, byte]
  server, opened, invalid: bool
  admitted, rejected, closed: int
  refusal: AdmissionError

proc `=copy`(destination: var Party, source: Party) {.error.}
  ## Copying cannot relocate a live native callback context.

proc `=dup`(source: Party): Party {.error.}
  ## Duplicating its foreign retirement authority is also forbidden.

proc key(path: string): array[32, byte] {.raises.} =
  ## Public fixture keys have exact32-byte identity width.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Certificate/SAN checks precede TLS proof of possession and the later policy decision.
  let owner = cast[ptr Party](user)
  if owner.server: return cint(validPeer(cast[ptr byte](der), length, []))
  cint(validPeer(cast[ptr byte](der), length, owner.pin))

proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## No application streams are needed to prove authenticated capacity classification.
  if event == 0: streamAbort(handle)

proc matches(bytes: ptr ConstByte, length: csize_t, expected: string): bool =
  ## Compare only a fully bounded exact negotiated protocol span.
  if bytes == nil or length != csize_t(expected.len): return false
  let raw = cast[ptr UncheckedArray[byte]](bytes)
  for index in 0..<expected.len:
    if raw[index] != byte(expected[index]): return false
  true

proc admit(user: pointer, slot: cuint, der: ptr ConstByte, length: csize_t,
    protocol: ptr ConstByte, protocolLength: csize_t): cint {.cdecl, raises: [].} =
  ## Copy Ed25519 identity from authenticated DER, never trust a separately supplied network key.
  let owner = cast[ptr Party](user)
  var fields {.noinit.}: CertFields
  if der == nil or length == 0 or parseCert(cast[ptr byte](der), length, addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32:
    owner.invalid = true
    return 0 # Missing primitive identity cannot consume any capacity class.
  let builder = matches(protocol, protocolLength, "jamnp-s/1/00000000/builder")
  if not builder and not matches(protocol, protocolLength, "jamnp-s/1/00000000"):
    owner.invalid = true
    return 0 # Only the server's exact configured domain is usable.
  var identity = default(array[32, byte])
  for index in 0..<32: identity[index] = fields.key[index]
  let admitted = owner.policy.admitAuthenticated(PeerSlot(uint64(slot)), StateEdKey(identity), builder)
  if admitted.error != AdmissionError.None:
    owner.refusal = admitted.error
    inc owner.rejected
    return 0 # Failure leaves policy ownership/counts unchanged before native refusal.
  1

proc peer(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  ## Native closure, rather than a logical rejection or client TLS flag, releases the reservation.
  let owner = cast[ptr Party](user)
  if event == PeerAccepted:
    inc owner.admitted
  elif event == PeerClosed:
    if not owner.policy.release(PeerSlot(uint64(slot))): owner.invalid = true
    inc owner.closed
  else: owner.invalid = true # Unknown primitive observations cannot alter role ownership.

proc connect(client: var Party, port: uint16, builder: bool) {.raises.} =
  ## Same authenticated peer deliberately requests different reservation classes over time.
  client.pin = key(getEnv("RAGNAROK_TEST_PEER_A"))
  let protocol = if builder: "jamnp-s/1/00000000/builder" else: "jamnp-s/1/00000000"
  assert client.transport.openTransport(false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), protocol, addr client, verify, stream)
  client.opened = true
  assert client.transport.connectTransport(port)

proc pump(server: var Party, clients: var array[2, Party], accepted, rejected, closed: int) =
  ## Observe exact server policy/native milestones with a finite wall-clock deadline.
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0)
    for index in 0..<clients.len:
      if clients[index].opened: assert clients[index].transport.pollTransport(0)
    assert not server.invalid
    if server.admitted == accepted and server.rejected == rejected and server.closed == closed: return
  assert false, "validator TLS policy milestones timed out"

proc policyTls*() {.raises.} =
  ## Validator identity overrides builder ALPN; after finalized removal, only the builder reserve fits.
  var server = Party(server: true)
  var clients = default(array[2, Party])
  defer:
    for index in 0..<clients.len: clients[index].transport.closeTransport()
    server.transport.closeTransport() # The policy remains alive through final foreign callbacks.
  let own = StateEdKey(key(getEnv("RAGNAROK_TEST_PEER_A")))
  let remote = StateEdKey(key(getEnv("RAGNAROK_TEST_PEER_B")))
  var rosters = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
  rosters[0][0].ed25519 = own
  rosters[0][1].ed25519 = remote
  let seed = topologyCaptured(rosters)
  let projected = captureValidatorTopology(seed, topologyLimits())
  assert projected.error == TopologyError.None
  server.policy = initValidatorAdmission(projected.value, own, 1, 1, 0).value
  assert server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, verify, stream,
    multi = true, incomingPeers = server.policy.capacity, acceptedAlpns = serverAlpns("jamnp-s/1/00000000"))
  assert server.transport.admitPeers(admit) and server.transport.observePeers(peer)
  connect(clients[0], localPort(server.transport), true)
  pump(server, clients, 1, 0, 0) # Establish the retained generation before testing its duplicate.
  connect(clients[1], localPort(server.transport), false)
  pump(server, clients, 1, 1, 0)
  assert server.refusal == AdmissionError.Duplicate
  assert server.policy.count(PeerClass.Validator) == 1 and server.policy.count(PeerClass.Builder) == 0
  clients[0].transport.disconnectTransport()
  pump(server, clients, 1, 1, 1)
  for index in 0..<clients.len:
    clients[index].transport.closeTransport()
    clients[index].opened = false # A closed generation releases its stable client slot before reuse.
  let after = [topologyRecords(3, 6), topologyRecords(4, 9), topologyRecords(5, 12)]
  let child = topologyCaptured(after, atSlot = 12, parent = seed)
  let advanced = advanceView(genesisView(seed), child)
  assert advanced.error == ViewAdvanceError.None
  let finalized = finalizeView(advanced.value, child.value.blockHash)
  assert finalized.error == ViewFinalizeError.None
  assert server.policy.advance(finalized.value, StateTime(13), topologyLimits()).value ==
      EpochUpdate.Applied
  connect(clients[0], localPort(server.transport), false)
  pump(server, clients, 1, 2, 1)
  assert server.refusal == AdmissionError.Full # Ordinary peers cannot take the idle builder reserve.
  clients[0].transport.closeTransport()
  clients[0].opened = false
  connect(clients[1], localPort(server.transport), true)
  pump(server, clients, 2, 2, 1)
  assert server.policy.count(PeerClass.Validator) == 0 and server.policy.count(PeerClass.Builder) == 1
