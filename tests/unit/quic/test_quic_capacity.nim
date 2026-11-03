# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real bounded shared dispatch, fair UDP batches and native TLS admission beyond the legacy16 slots.
import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/quic/[io, transport]
import ../../../src/jamnp-s/protocol

const Peers = 20

type Party = object ## Stable callback owner; all native engines close before any surrounding storage retires.
  transport: Transport
  anyKey, opened, invalid: bool
  pin: array[32, byte]
  live: array[Peers, bool]
  admitted, retired: int
proc `=copy`(destination: var Party, source: Party) {.error.}
  ## Copying the aggregate would leave native callbacks pointing into a different enclosing owner.
proc `=dup`(source: Party): Party {.error.}
  ## Duplication cannot create another retirement authority for an existing endpoint.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Capacity never replaces normal TLS/SAN validation or the dialer's exact server identity pin.
  let owner = cast[ptr Party](user)
  if owner.anyKey: return cint(validPeer(cast[ptr byte](der), length, []))
  cint(validPeer(cast[ptr byte](der), length, owner.pin))
proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Admission requires no application streams; unsolicited streams retain no test payload.
  if event == 0: streamAbort(handle)
proc peer(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  ## Each accepted slot remains occupied until its genuine close callback, including after reuse.
  let owner = cast[ptr Party](user)
  if slot >= cuint(Peers): owner.invalid = true; return
  let index = int(slot)
  if event == 0:
    if owner.live[index] or owner.admitted >= Peers+4 or der == nil or length == 0:
      owner.invalid = true
      return # An invalid observation cannot index storage, duplicate admission or increment an unbounded counter.
    if not validPeer(cast[ptr byte](der), length, []): owner.invalid = true; return
    owner.live[index] = true
    inc owner.admitted
  elif event == 1:
    if not owner.live[index] or owner.retired >= Peers+4: owner.invalid = true; return
    owner.live[index] = false
    inc owner.retired
  else: owner.invalid = true # Unknown primitive event kinds never become successful admission.

proc key(path: string): array[32, byte] {.raises.} =
  ## Copy only a complete generated public fixture key; PEM/private-key storage is unrelated.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])

proc waitAll(dispatcher: Dispatcher) =
  ## Kernel delivery may lag sendto; establish permanent readiness before measuring fair batch order.
  var all = default(array[12, Ready])
  let started = getMonoTime()
  while dispatcher.wait(10, all) != all.len:
    assert (getMonoTime()-started).inSeconds < 2, "all local datagrams became readable"

proc datagrams() =
  ## Every permanently ready socket gets a turn even when the caller can hold only three events.
  const Count = 12
  let dispatcher = newDispatcher(Count)
  var endpoints = default(array[Count, UdpEndpoint])
  var extra = default(UdpEndpoint)
  defer:
    extra.close()
    for index in 0..<Count: endpoints[index].close() # Socket retirement removes copied registrations before metadata closes.
    dispatcher.close()
  assert dispatcher.capacity == Count and dispatcher.registrationCount == 0
  for index in 0..<Count:
    assert endpoints[index].open(false, 0)
    assert dispatcher.register(endpoints[index])
  assert extra.open(false, 0) and not dispatcher.register(extra)
  var payload = [71'u8]
  for index in 0..<Count:
    assert endpoints[0].send(addr payload[0], payload.len, endpoints[index].port) == 1
  var ready = default(array[3, Ready])
  assert dispatcher.wait(0, ready) == -1 # Legacy waits still refuse an undersized all-registration output.
  var empty = default(array[0, Ready])
  assert dispatcher.waitBatch(0, empty) == -1
  waitAll(dispatcher) # Priming observes but never consumes any packet.
  var seen = default(array[Count, bool])
  for turn in 0..<4:
    let count = dispatcher.waitBatch(0, ready)
    assert count == 3, "fair ready batch: " & $count
    for event in ready:
      assert not event.failed
      var found = false
      for index in 0..<Count:
        if event.descriptor == endpoints[index].descriptor:
          assert not seen[index] # Rotation cannot keep returning an earlier ready socket while siblings starve.
          seen[index] = true; found = true
      assert found
  for index in 0..<Count:
    assert seen[index]
    var received = default(array[1, byte])
    var source = 0'u16
    assert endpoints[index].receive(received, source) == 1 and received == payload
  let retired = endpoints[3].descriptor
  endpoints[3].close() # Closing a registered owner compacts the table and retires its descriptor.
  assert dispatcher.registrationCount == Count-1 and dispatcher.register(extra)
  for index in 0..<Count:
    if index != 3: assert endpoints[0].send(addr payload[0], payload.len, endpoints[index].port) == 1
  assert endpoints[0].send(addr payload[0], payload.len, extra.port) == 1
  waitAll(dispatcher) # New registrations also become readable before their batch-order witness.
  var copied = 0
  for turn in 0..<4:
    let count = dispatcher.waitBatch(0, ready)
    assert count == 3, "retirement ready batch: " & $count
    for event in ready:
      assert not event.failed and event.descriptor != retired
      var received = default(array[1, byte])
      var source = 0'u16
      var found = false
      if event.descriptor == extra.descriptor:
        assert extra.receive(received, source) == 1
        found = true
      else:
        for index in 0..<Count:
          if index != 3 and event.descriptor == endpoints[index].descriptor:
            assert endpoints[index].receive(received, source) == 1
            found = true # Every copied ready descriptor still belongs to exactly one current registration.
      assert found and received == payload
      inc copied
  assert copied == Count and dispatcher.waitBatch(0, ready) == 0
  dispatcher.close()
  assert dispatcher.capacity == 0 and dispatcher.waitBatch(0, ready) == -1
  let maximum = newDispatcher(MaxDispatcherEndpoints)
  assert maximum.capacity == MaxDispatcherEndpoints
  maximum.close()

proc advance(server: var Party, clients: var array[Peers+2, Party], dispatcher: Dispatcher) =
  ## One shared wait routes copied events to their exact owner; native timers never perform nested waits.
  assert server.transport.processTimers()
  for index in 0..<clients.len:
    if clients[index].opened: assert clients[index].transport.processTimers()
  var ready = default(array[MaxReadyBatch, Ready])
  let count = dispatcher.waitBatch(0, ready)
  assert count >= 0
  for index in 0..<count:
    var found = false
    if server.transport.ownsReady(ready[index]):
      assert server.transport.processReady(ready[index])
      found = true
    else:
      for client in 0..<clients.len:
        if clients[client].opened and clients[client].transport.ownsReady(ready[index]):
          assert clients[client].transport.processReady(ready[index])
          found = true
    assert found # No endpoint is retired or replaced in the middle of this ready batch.
  assert not server.invalid, "peer observation invalid: admitted=" & $server.admitted &
      " retired=" & $server.retired

proc connect(client: var Party, dispatcher: Dispatcher, port: uint16, ipv6: bool) {.raises.} =
  ## Engines retain stable outer addresses and share only descriptor metadata, never callback contexts.
  client.pin = key(getEnv("RAGNAROK_TEST_PEER_A"))
  assert client.transport.openTransport(false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "capacity/v1", addr client, verify, stream,
    ipv6 = ipv6, dispatcher = dispatcher)
  client.opened = true
  assert client.transport.connectTransport(port)

proc admission(ipv6: bool) {.raises.} =
  ## The same explicit multi-peer policy works for IPv4 and the IPv6 validator endpoint family.
  let dispatcher = newDispatcher(Peers+4)
  var server = default(Party)
  var clients = default(array[Peers+2, Party])
  defer:
    for index in 0..<clients.len: clients[index].transport.closeTransport()
    server.transport.closeTransport()
    dispatcher.close() # Every engine/socket retires before the shared descriptor metadata.
  server.anyKey = true
  assert server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "capacity/v1", addr server, verify, stream,
    multi = true, ipv6 = ipv6, dispatcher = dispatcher, incomingPeers = Peers)
  assert server.transport.observePeers(peer), "configured peer observer"
  let port = server.transport.localPort
  for index in 0..<Peers+1: clients[index].connect(dispatcher, port, ipv6)
  let started = getMonoTime()
  while server.admitted != Peers or server.transport.peerMetric(5) == 0:
    assert (getMonoTime()-started).inSeconds < 20, "twenty admitted and overflow refused"
    server.advance(clients, dispatcher)
  assert server.transport.peerMetric(0) == uint64(Peers)
  assert server.transport.peerMetric(3) == uint64(Peers)
  # TLS success precedes server admission; wait until the rejected connection actually retires on its client.
  while true:
    var retained = 0
    var authenticated = 0
    for index in 0..<Peers+1:
      let live = clients[index].transport.peerMetric(0)
      assert live <= 1 # A client engine still has its independent single-connection ceiling.
      if live == 1:
        inc retained
        if clients[index].transport.transportStatus == 1: inc authenticated
    if retained == Peers and authenticated == Peers: break
    assert (getMonoTime()-started).inSeconds < 20, "overflow client retired"
    server.advance(clients, dispatcher)
  assert server.retired == 0
  # Close a retained authenticated client; the overflow attempt is not assumed to have any particular index.
  var selected = -1
  for index in 0..<Peers+1:
    if clients[index].transport.peerMetric(0) == 1 and clients[index].transport.transportStatus == 1:
      selected = index
  assert selected >= 0
  clients[selected].transport.disconnectTransport()
  while server.retired == 0:
    assert (getMonoTime()-started).inSeconds < 20, "native slot retirement"
    server.advance(clients, dispatcher)
  clients[selected].transport.closeTransport()
  clients[selected].opened = false
  clients[Peers+1].connect(dispatcher, port, ipv6)
  while server.admitted != Peers+1:
    assert (getMonoTime()-started).inSeconds < 20, "vacant slot reused"
    server.advance(clients, dispatcher)
  assert server.retired == 1 and server.transport.peerMetric(0) == uint64(Peers)
  assert server.transport.peerMetric(3) == uint64(Peers) and not server.invalid

proc refused() =
  ## Valid certificate inputs isolate invalid resource policies from unrelated TLS setup failures.
  var owner = default(Party)
  defer: owner.transport.closeTransport()
  let certificate = getEnv("RAGNAROK_TEST_CERT")
  let privateKey = getEnv("RAGNAROK_TEST_KEY")
  var invalid = @[-1, 0, MaxIncomingPeers+1]
  when sizeof(int) == 8:
    invalid.add(int(0x1_0000_0010'u64)) # Narrowing this untrusted count to uint32 would turn it into the valid default16.
  for maximum in invalid:
    assert not owner.transport.openTransport(true, false, 0, certificate, privateKey, "capacity/v1",
      addr owner, verify, stream, multi = true, incomingPeers = maximum)
    assert owner.transport.localPort == 0 and owner.transport.transportStatus == -1
  assert not owner.transport.openTransport(false, false, 0, certificate, privateKey, "capacity/v1",
    addr owner, verify, stream, incomingPeers = 2)
  assert not owner.transport.openTransport(false, false, 0, certificate, privateKey, "capacity/v1",
    addr owner, verify, stream, ipv6 = true, multi = true)

try:
  datagrams()
  echo "UDP_CAPACITY fair batches and retirement passed"
  refused()
  echo "CAPACITY_POLICY invalid limits rejected"
  admission(false)
  echo "TLS_CAPACITY ipv6=false twenty peers and slot reuse passed"
  admission(true)
  echo "TLS_CAPACITY ipv6=true twenty peers and slot reuse passed"
except:
  quit 2 # Environment/native setup exceptions are never passing capacity evidence.
echo "QUIC shared capacity, fair batches, twenty-peer admission and slot reuse passed"
