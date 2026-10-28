# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real local HTTP client with independent framing and bounded nonblocking receive polling.
import std/assertions
import std/strutils
import std/nativesocket
import std/posix/posix
import ../../src/management/server as management_server

type LocalEndpoint = object ## POSIX local-address prefix with a bounded pathname and final NUL.
  when defined(macosx):
    length, family: uint8
  else:
    family: cushort
  path: array[104, char]

proc openSocket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Test clients use an actual local stream socket.
proc connectSocket(fd: cint, endpoint: pointer, size: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## Connect to the explicitly enabled management pathname.
proc sendBytes(fd: cint, bytes: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Send the initialized HTTP request once, independently of the server parser.
proc receive(fd: cint, bytes: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Copy no more than one bounded native response chunk.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bound retries without a blocking read or indefinite test deadline.

proc managementInfo*(server: var ManagementServer, path: string): string =
  ## Only the management listener is polled; callers can verify RPC/canonical leases stay active.
  assert path.len > 0 and path.len < 104
  let peer = openSocket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert peer >= 0
  defer: discard posix.close(peer) # Failure assertions terminate; normal replies release the native client.
  var endpoint = default(LocalEndpoint)
  endpoint.family = typeof(endpoint.family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): endpoint.length = uint8(sizeof(endpoint)) # Darwin requires the address extent.
  for index, c in path: endpoint.path[index] = c
  assert connectSocket(peer, addr endpoint, SockLen(sizeof(endpoint))) == 0
  let flags = fcntl(peer, F_GETFL, 0)
  assert flags >= 0 and fcntl(peer, F_SETFL, flags or O_NONBLOCK) == 0
  const body = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_unsafe_clientInfo\",\"id\":1}"
  var request = "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: " &
    $body.len & "\r\n\r\n" & body
  assert sendBytes(peer, request.toCString(), csize_t(request.len), 0) == request.len
  result = ""
  for attempt in 0..<200:
    server.tick()
    var bytes = default(array[4096, char])
    let count = receive(peer, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: result.add(bytes[index]) # Receive bounds precede every initialized-byte access.
      assert result.len <= 16384
    elif count == 0:
      assert "200 OK" in result and "\"result\"" in result
      return # The management server closes after exactly one complete response.
    discard pauseMicros(1000)
  assert false, "management response deadline"
