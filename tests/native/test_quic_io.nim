## Exercise the production UDP/readiness adapter without a TLS engine or compiler/runtime hooks.
import std/[assertions, syncio]
import std/posix/posix
import ../../src/quic/io

let
  # Read the actual OS flag independently through public C headers, not wrapper bookkeeping.
  GetFdFlags {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint

# Shared dispatch keeps both sockets active and routes copied datagrams to their correct owner.
proc shared(ipv6: bool) =
  let dispatcher = newDispatcher()
  defer: dispatcher.close()
  var a, b, extra: UdpEndpoint = default(UdpEndpoint)
  assert a.open(ipv6, 0) and b.open(ipv6, 0) and extra.open(ipv6, 0)
  defer: a.close()
  defer: b.close()
  defer: extra.close()
  assert (fcntl(a.descriptor, F_GETFL) and O_NONBLOCK) != 0
  assert (fcntl(a.descriptor, GetFdFlags) and CloseExec) != 0
  assert dispatcher.register(a) and dispatcher.register(b)
  assert not dispatcher.register(extra)
  let other = newDispatcher()
  defer: other.close()
  assert not other.register(a)
  other.unregister(a) # A different dispatcher cannot retire this live registration.
  var short = default(array[1, Ready])
  assert dispatcher.wait(0, short) == -1
  var ready = default(array[2, Ready])
  var payload = [42'u8, 17'u8]
  assert a.send(addr payload[0], 2, b.port) == 2
  assert b.send(addr payload[0], 2, a.port) == 2
  # Both packets are synchronously queued before the bounded wait starts.
  assert dispatcher.wait(10, ready) == 2
  assert ready[0].descriptor != ready[1].descriptor
  var received = default(array[2, byte])
  var source: uint16 = 0
  assert a.receive(received, source) == 2 and received == payload and source == b.port
  assert b.receive(received, source) == 2 and received == payload and source == a.port
  assert dispatcher.wait(0, ready) == 0
  # Failed open must release its descriptor and preserve an existing live endpoint.
  assert not extra.open(ipv6, 0)
  var occupied = default(UdpEndpoint)
  assert not occupied.open(ipv6, a.port) and not occupied.isOpen
  assert a.send(addr payload[0], -1, b.port) == -1
  assert a.send(addr payload[0], 2049, b.port) == -1
  dispatcher.unregister(a)
  dispatcher.unregister(b)
  assert dispatcher.register(extra)
  dispatcher.unregister(extra)
  dispatcher.close()
  dispatcher.close()
  assert dispatcher.wait(0, ready) == -1 and not dispatcher.register(a)
  echo "UDP_SHARED ipv6=", ipv6, " passed"

# Automatic scope retirement must remove metadata and close sockets without an explicit close call.
proc scoped(ipv6: bool) =
  let dispatcher = newDispatcher()
  defer: dispatcher.close()
  var ready = default(array[2, Ready])
  # More scopes than dispatcher capacity detect a missing destructor/unregister immediately.
  for iteration in 0..<256:
    var retiredPort: uint16 = 0
    block:
      var endpoint = default(UdpEndpoint)
      assert endpoint.open(ipv6, 0) and dispatcher.register(endpoint)
      retiredPort = endpoint.port
      var payload = [1'u8]
      assert endpoint.send(addr payload[0], 1, endpoint.port) == 1
      assert dispatcher.wait(10, ready) == 1
    assert dispatcher.wait(0, ready) == 0
    # Successful rebind proves the destructor closed the OS socket, not only its metadata.
    var rebound = default(UdpEndpoint)
    assert rebound.open(ipv6, retiredPort)
    rebound.close()
  echo "UDP_SCOPED ipv6=", ipv6, " rounds=256"

# Drop an isolated metadata/socket scope through explicit or automatic cleanup.
proc metadataScope(explicitClose: bool) =
  let dispatcher = newDispatcher()
  var endpoint = default(UdpEndpoint)
  assert endpoint.open(false, 0) and dispatcher.register(endpoint)
  if explicitClose:
    # Clearing the owned dispatcher field explicitly must not make scope destruction release it twice.
    endpoint.close()
    endpoint.close()
  dispatcher.close()

# Observe public live occupancy after warmup; no private ARC counters or allocator hooks are used.
proc metadataLifetimes() =
  for i in 0..<20: metadataScope(i mod 2 == 0) # Warm the same two cleanup paths.
  let before = getOccupiedMem()
  # Every dispatcher must release its final reference after its unique socket leaves scope.
  for i in 0..<1000: metadataScope(i mod 2 == 0)
  let after = getOccupiedMem()
  assert before == after
  echo "QUIC_IO_ARC_RELEASE cycles=1000 occupied_before=", before, " occupied_after=", after

# Both loopback families must work without depending on the still-unported authenticated peer.
retirementSelfTest(false)
retirementSelfTest(true)
shared(false)
shared(true)
scoped(false)
scoped(true)
metadataLifetimes()
echo "Nimony UDP readiness/retirement checks passed"
