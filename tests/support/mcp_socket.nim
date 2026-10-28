# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded independent HTTP client for live MCP application tests.
import std/[assertions, strutils]
import std/posix/posix
import ../../src/app/services
import ./rpc_socket as sockets

proc receive(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Receive only initialized bytes from a real local connection.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bounded polling never blocks indefinitely on local transport progress.
proc mcpTool*(owner: var Services, port: uint16, tool: string, arguments = "{}"): string =
  ## Independent HTTP client exercises the dispatcher rather than direct protocol calls.
  let peer = sockets.client(port)
  defer: discard posix.close(peer)
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"" &
      tool & "\",\"arguments\":" & arguments & "}}"
  let request = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:" & $port &
    "\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: " &
        $body.len & "\r\n\r\n" & body
  sockets.sendText(peer, request, masked = false)
  result = ""
  for attempt in 0..<200:
    owner.tick(2)
    var buffer = default(array[8192, char])
    let count = receive(peer, addr buffer[0], 8192, 0)
    if count > 0:
      for index in 0..<count: result.add(buffer[index])
    elif count == 0: return # Connection closes only after all reply bytes drain.
    discard pauseMicros(1000)
  assert false, "MCP service response deadline"
