# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared RPC test reads tolerate a delayed producer and still reject an absent packet by deadline.
import std/[assertions, syncio, monotimes, times, strutils]
import std/posix/posix
import ../../../src/rpc/server
import ../../support/rpc_socket

proc socketPair(domain, kind, protocol: cint, descriptors: ptr cint): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Keep both real stream endpoints owned by this test without ephemeral TCP port races.
proc armTimeout(seconds: cuint): cuint {.importc: "alarm", header: "<unistd.h>".}
  ## An independent process deadline prevents a broken packet deadline from hanging the suite.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield while the independent producer deliberately withholds its packet.

proc endpoints(): array[2, cint] =
  ## Packet reads require a nonblocking receiver, just like the shared loopback client.
  result = [-1.cint, -1.cint]
  assert socketPair(AF_UNIX, SOCK_STREAM, 0, addr result[0]) == 0
  let flags = fcntl(result[0], F_GETFL, 0)
  assert flags >= 0 and fcntl(result[0], F_SETFL, flags or O_NONBLOCK) == 0

proc delayed(header: bool) =
  ## A producer waits past the former 200 ms budget; the reader must accept exact bytes without a retry.
  let pair = endpoints()
  defer:
    discard posix.close(pair[0])
    discard posix.close(pair[1])
  let child = posix.fork()
  assert child >= 0
  if child == 0:
    discard armTimeout(5)
    discard posix.close(pair[0])
    let started = getMonoTime()
    while (getMonoTime() - started).inMilliseconds < 400:
      discard pauseMicros(1000) # Interruptions cannot shorten the intended producer delay.
    var wire = "\x81\x02ok\x81\x04next"
    if header:
      wire = "HTTP/1.1 101 Switching Protocols\r\n\r\n" & wire # Coalesced frames survive header consumption.
    if posix.write(pair[1], wire.toCString(), wire.len) != wire.len:
      posix.exitnow(3) # A broken writer cannot count as successful delayed delivery.
    posix.exitnow(0)
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0) # A failed reader never leaves its independent producer alive.
  var rpc = default(Server)
  var pending = ""
  if header:
    upgrade(rpc, pair[0], pending) # The public handshake helper shares the same delayed-read budget.
  assert readPacket(rpc, pair[0], pending, description = "delayed response") == "ok"
  assert readPacket(rpc, pair[0], pending, description = "coalesced suffix") == "next"
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0

proc absent() =
  ## A live but silent peer must fail at the requested deadline with the exact phase diagnostic.
  let pair = endpoints()
  defer:
    discard posix.close(pair[0])
    discard posix.close(pair[1])
  var channel = [-1.cint, -1.cint]
  assert posix.pipe(addr channel[0]) == 0
  let child = posix.fork()
  assert child >= 0
  if child == 0:
    discard armTimeout(5)
    discard posix.close(channel[0])
    if posix.dup2(channel[1], 1) != 1: posix.exitnow(98)
    if posix.dup2(channel[1], 2) != 2: posix.exitnow(98)
    discard posix.close(channel[1])
    var rpc = default(Server)
    var pending = ""
    discard readPacket(rpc, pair[0], pending, description = "absent response control",
        timeoutMs = 50)
    posix.exitnow(99) # Returning an empty/default packet is never a successful timeout control.
  discard posix.close(channel[1])
  var diagnostic = ""
  var buffer = default(array[256, char])
  while true:
    let count = posix.read(channel[0], addr buffer[0], buffer.len)
    if count > 0:
      for index in 0..<count:
        if diagnostic.len < 4096: diagnostic.add(buffer[index]) # Drain all output without unbounded retention.
    elif count == 0 or posix.errno() != EINTR:
      break # EOF ends the actual child's diagnostic; unrelated IO failures cannot fabricate it.
  discard posix.close(channel[0])
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  assert WIFEXITED(status) and WEXITSTATUS(status) == 1
  assert "RPC packet did not arrive within 50 ms: absent response control" in diagnostic

delayed(false)
delayed(true)
absent()
echo "RPC socket deadlines passed"
