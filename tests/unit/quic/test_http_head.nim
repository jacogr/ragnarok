# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real Balsa parsing preserves the authorization boundary, owned fields and stock syntax.

import std/[assertions, strutils, syncio]
import ../../../src/lib/http_head

block:
  # Fragment every head byte, then leave the coalesced application body untouched.
  var head = default(Head)
  let wire = "POST /mcp HTTP/1.1\r\nHost: localhost:14141\r\nContent-Length: 2\r\nX-Client: a\tb\r\n\r\n"
  var input = ""
  for index in 0..<wire.len-1:
    input.add(wire[index])
    assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == HeadPending
  input.add(wire[^1])
  input.add("{}next")
  assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == wire.len
  assert head.methodOf == "POST" and head.target == "/mcp" and head.version == "HTTP/1.1"
  assert head.contentLength == 2 and head.hasHeader("CONTENT-LENGTH")
  assert input.substr(wire.len) == "{}next"
  input = "replaced caller storage"
  assert head.header("host") == "localhost:14141" and head.header("x-client") == "a\tb"
  var moved = move(head)
  assert moved.target == "/mcp"
  assert head.parse("GET /fresh HTTP/1.0\nHost: new\n\n")
  assert head.target == "/fresh" and moved.target == "/mcp"

block:
  # Application selectors keep original occurrences instead of a merged ambiguous value.
  var head = default(Head)
  assert head.parse("GET / HTTP/1.1\r\nHost: one\r\nhost: two\r\nX-Client: a\r\nx-client: b\r\n\r\n")
  assert head.headerCount("HOST") == 2 and head.headerCount("X-Client") == 2
  assert not head.hasHeader("Content-Length") and head.contentLength == 0

for length in ["000000", "18446744073709551615"]:
  # Content-Length uses the library's checked full unsigned width, without spelling limits.
  var head = default(Head)
  assert head.parse("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: " & length & "\r\n\r\n")
  assert head.contentLength == (if length == "000000": 0'u64 else: high(uint64))

for fields in ["Content-Length: 18446744073709551616\r\n",
    "Content-Length: 1\r\nContent-Length: 1\r\n",
    "Content-Length: 1\r\nTransfer-Encoding: chunked\r\n"]:
  # An ambiguous/overflowing body extent cannot authorize reads or expose a partial request.
  var head = default(Head)
  let input = "POST / HTTP/1.1\r\nHost: localhost\r\n" & fields & "\r\n"
  assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == HeadInvalid
  assert head.methodOf == "" and head.headerCount("host") == 0
  assert not head.parse("GET / HTTP/1.1\r\nHost: fresh\r\n\r\n")

block:
  # The native library's limit remains bounded and independently observable at the caller.
  var small, large = default(Head)
  assert small.parse("GET / HTTP/1.1\r\nHost: localhost\r\nX-Padding: " & repeat('x', 5000) & "\r\n\r\n")
  let input = "GET / HTTP/1.1\r\nX-Padding: " & repeat('x', int(maxHeadBytes()))
  assert large.findHeadEnd(toOpenArray(input, 0, input.len-1)) == HeadTooLarge
  large.close()
  assert large.parse("GET / HTTP/1.1\r\nHost: reset\r\n\r\n")

block:
  # Skipped blank lines still occupy the Reader's accumulated unread buffer.
  var head = default(Head)
  var input = ""
  let limit = int(maxHeadBytes())
  while input.len < limit:
    # Fragment both CR/LF pairs and the preamble itself across scans.
    input.add(if input.len mod 2 == 0: '\r' else: '\n')
    let expected = if input.len == limit: HeadTooLarge else: HeadPending
    assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == expected
  input.add("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
  assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == HeadTooLarge
  assert head.methodOf == "" and head.headerCount("host") == 0
  assert not head.parse("GET / HTTP/1.1\r\nHost: fresh\r\n\r\n")
  head.close()
  assert head.parse("GET / HTTP/1.1\r\nHost: reset\r\n\r\n")

block:
  # One oversized preamble cannot hide a valid head beyond the retained wire budget.
  var head = default(Head)
  let input = repeat("\r\n", int(maxHeadBytes())) & "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == HeadTooLarge
  assert head.target == "" and not head.hasHeader("host")

for exactLimit in [false, true]:
  # Balsa still accepts bounded blank lines, even with a body larger than the head budget.
  var head = default(Head)
  let limit = int(maxHeadBytes())
  let request = "POST /mcp HTTP/1.1\r\nHost: localhost\r\nContent-Length: " & $(limit*2) & "\r\n\r\n"
  let room = limit - request.len
  let preamble = if exactLimit: repeat("\r\n", room div 2) & repeat('\n', room mod 2) else: "\r\n"
  let wire = preamble & request
  let input = wire & repeat('b', limit*2)
  assert head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == wire.len
  assert head.target == "/mcp" and head.contentLength == uint64(limit*2)
  assert input.substr(wire.len) == repeat('b', limit*2)

echo "Balsa HTTP heads: fragmentation, ownership, framing and bounds passed"
