# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise the production UDP/readiness adapter without a TLS engine or compiler/runtime hooks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "quic_io_arc_release"}

import ../../support/arc_evidence
import std/[assertions, syncio, monotimes, times, oserrors]
import std/posix/posix
import ../../../src/quic/io

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
  # poll may return the first delivered datagram before the other socket becomes ready.
  # Consume each event under the original single 10 ms budget; never require simultaneous arrival.
  let started = getMonoTime()
  var seenA = false
  var seenB = false
  while not seenA or not seenB:
    let remaining = 10 - (getMonoTime() - started).inMilliseconds
    assert remaining > 0, "both loopback datagrams must arrive within 10 ms"
    let count = dispatcher.wait(int(remaining), ready)
    assert count > 0 and count <= 2, "expected bounded socket readiness"
    if count == 2:
      # One poll result must never route the same descriptor twice.
      assert ready[0].descriptor != ready[1].descriptor
    for i in 0..<count:
      # Only the two registered owners can supply a successful readiness event.
      assert not ready[i].failed
      var received = default(array[2, byte])
      var source: uint16 = 0
      if ready[i].descriptor == a.descriptor:
        # Drain the first owner's packet so subsequent waits can observe the other socket.
        assert not seenA
        assert a.receive(received, source) == 2 and received == payload and source == b.port
        seenA = true
      else:
        # The second owner's reply must retain both payload and source identity.
        assert ready[i].descriptor == b.descriptor and not seenB
        assert b.receive(received, source) == 2 and received == payload and source == a.port
        seenB = true
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
      assert endpoint.open(ipv6, 0) and dispatcher.register(endpoint), "scoped endpoint open/register"
      retiredPort = endpoint.port
      var payload = [1'u8]
      assert endpoint.send(addr payload[0], 1, endpoint.port) == 1, "scoped self-send"
      let started = getMonoTime()
      let count = dispatcher.wait(10, ready)
      # Preserve elapsed time and OS context when the unchanged readiness deadline fails.
      if count != 1:
        echo "SCOPED_WAIT ipv6=", ipv6, " iteration=", iteration, " count=", count, " elapsed_us=",
            (getMonoTime() - started).inMicroseconds, " errno=", osLastError().int
      assert count == 1, "scoped readiness"
    assert dispatcher.wait(0, ready) == 0, "scoped registration retirement"
    # Successful rebind proves the destructor closed the OS socket, not only its metadata.
    var rebound = default(UdpEndpoint)
    assert rebound.open(ipv6, retiredPort), "scoped port rebind"
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
  # Preserve fresh numeric observations independently of portable expected output.
  recordArcRelease("quic_io", 1000, before, after)
  echo "QUIC_IO_ARC_RELEASE cycles=1000 unchanged"

# Both loopback families must work without depending on the still-unported authenticated peer.
retirementSelfTest(false)
retirementSelfTest(true)
shared(false)
shared(true)
scoped(false)
scoped(true)
metadataLifetimes()
echo "Nimony UDP readiness/retirement checks passed"
