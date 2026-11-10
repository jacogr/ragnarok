# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone pinned-library retirement probe; not a passing application test or submitted issue.

import std/[assertions, syncio]
import std/http/httpmsg as msg
import std/http/httpparse as parser

let tags = msg.newHttpTags() # One shared vocabulary for the process, as documented.

proc parseOne() =
  var head = msg.initHttpMsg(tags)
  let wire = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  assert parser.parseRequestHead(toOpenArray(wire, 0, wire.len - 1), head) == wire.len
  assert head.getStr(msg.hHost) == "localhost"

for index in 0..<10: parseOne()
let baseline = getOccupiedMem()
for index in 0..<100: parseOne()
let retained = getOccupiedMem() - baseline
echo "retained bytes after 100 retired messages: ", retained
assert retained <= 256, "retired HTTP messages release their owned storage"
