# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included after the RPC server so tests can attach socket pairs to its production stream
## owners and drive the real dispatcher. The client side retains only its own descriptor.

import std/[nativesocket, oserrors, strutils]
import ./rpc_socket as fixture_socket
from ../../src/lib/stop_signal import ignorePipeSignal
from std/ioring import boundPort, shutdown

assert ignorePipeSignal() # Match the executable’s stream signal policy.

const FixtureUpgrade = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
let fixtureSendBuffer {.importc: "SO_SNDBUF", header: "<sys/socket.h>".}: cint

proc fixturePair(domain, kind, protocol: cint, pair: pointer): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Provide a real connected descriptor without relying on TCP backpressure thresholds.

proc fixturePause(micros: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let passive stream tasks schedule between foreground polling turns.

proc fixtureListen(owner: var Server, role: string, parameters = unavailableParameters(),
    genesis = unavailableGenesis()) =
  ## Adopt an already bound ephemeral listener. Public start uses port zero to disable RPC.
  assert owner.availableForStart
  owner.fd = listenLoopback(0, cint(MaxConnections))
  assert owner.fd >= 0
  owner.opened = true
  let port = boundPort(owner.fd)
  assert port > 0
  owner.initializeContext(port, role, parameters, genesis, 0, default(ChainIdentity))

proc fixtureAttach(owner: var Server, index: int, sendBuffer = 0): cint =
  ## The worker takes the server endpoint. The caller closes the returned client endpoint.
  assert not owner.connections[index].opened
  owner.connections[index].stream = default(RpcWireStream) # Join the prior generation before reusing its slot.
  var pair = default(array[2, cint])
  assert fixturePair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0,
    addr pair[0]) == 0
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  if sendBuffer > 0:
    var requested = cint(sendBuffer)
    assert setOption(pair[0], SocketLevel, fixtureSendBuffer, addr requested,
      SockLen(sizeof(requested))) == 0
  assert owner.connections[index].stream.start(pair[0])
  owner.connections[index].opened = true
  owner.connections[index].deadline = getMonoTime().ticks div 1_000_000 + 5000
  pair[1]

proc fixtureBytes(owner: var Server, peer: cint, size: int): string =
  ## Read only the expected extent, leaving pipelined frames in the kernel for later assertions.
  result = ""
  for turn in 0..<2000:
    if result.len == size: return
    var buffer = default(array[4096, char])
    let count = receive(peer, addr buffer[0], csize_t(min(buffer.len, size - result.len)), 0)
    if count > 0:
      for index in 0..<count: result.add(buffer[index])
    else:
      assert count < 0 and retryableSocketError(osLastError()), "RPC fixture closed before its expected bytes"
      owner.tick(0)
      discard fixturePause(1000)
  assert false, "RPC fixture did not receive " & $size & " bytes"

proc fixtureFrame(owner: var Server, peer: cint): string =
  ## Read one unmasked short or medium frame without using the server decoder or losing a suffix.
  result = owner.fixtureBytes(peer, 2)
  let length = ord(result[1])
  assert length <= 126
  if length == 126:
    result.add(owner.fixtureBytes(peer, 2))
    result.add(owner.fixtureBytes(peer, ord(result[2]) * 256 + ord(result[3])))
  else:
    result.add(owner.fixtureBytes(peer, length))

proc fixtureConnect(owner: var Server, index: int, sendBuffer = 0): cint =
  ## Upgrade a fresh stream before a test drives its RPC/session policy.
  result = owner.fixtureAttach(index, sendBuffer)
  fixture_socket.sendText(result, FixtureUpgrade, false)
  let expected = upgrade(FixtureUpgrade)
  assert expected.startsWith("HTTP/1.1 101 ")
  assert owner.fixtureBytes(result, expected.len) == expected

proc fixtureBuffered(owner: var Server, index: int) =
  ## Wait for the actual Reader to retain bytes of an incomplete frame.
  for turn in 0..<1000:
    owner.tick(0)
    if owner.connections[index].stream.hasBufferedInput: return
    discard fixturePause(1000)
  assert false, "RPC fixture failed to buffer its partial input"

proc fixtureEof(owner: var Server, peer: cint) =
  ## A refused HTTP head or stopped stream closes without an extra response.
  var octet = '\0'
  for turn in 0..<2000:
    owner.tick(0)
    let count = receive(peer, addr octet, 1, 0)
    if count == 0: return
    assert count < 0 and retryableSocketError(osLastError())
    discard fixturePause(1000)
  assert false, "RPC fixture did not close within its retirement budget"
