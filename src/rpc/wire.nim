# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded RFC 6455 framing and UTF-8 validation; owned strings never retain socket buffers.
##
## Exposes UTF-8 validation, WebSocket upgrade/framing and incremental frame decoding with
## checked payload/status access.

import std/[strutils, base64, sha1]

const MaxMessage* = 16384
const MaxHeader* = 4096

# Validate Unicode scalar encodings, excluding overlong sequences, surrogates and out-of-range values.
proc validUtf8*(text: string): bool =
  var i = 0
  while i < text.len: # Each iteration consumes one complete Unicode scalar.
    let first = ord(text[i])
    inc i
    if first < 128: continue # ASCII needs no continuation bytes.
    var count = 0
    var value = 0
    var minimum = 0
    if first in 194..223: # Two-byte sequences cannot start with an overlong lead.
      count = 1; value = first and 31; minimum = 128
    elif first in 224..239: # Three-byte scalars must exclude UTF-16 surrogates.
      count = 2; value = first and 15; minimum = 2048
    elif first in 240..244: # Four-byte scalars stop at U+10FFFF.
      count = 3; value = first and 7; minimum = 65536
    else: return false # A continuation or reserved lead cannot begin a scalar.
    if count > text.len - i: return false # No truncated multibyte sequence.
    for j in 0..<count: # Bound every continuation before constructing the scalar.
      let part = ord(text[i])
      inc i
      if part notin 128..191: return false
      value = value * 64 + (part and 63)
    if value < minimum or value > 0x10ffff or value in 0xd800..0xdfff: return false
  true

# Produce one unmasked final server frame; caller supplies a bounded payload and valid opcode.
proc frame*(payload: string, opcode = 1): string =
  result = ""
  if payload.len > 65535: return # The server's bounded response policy never needs a 64-bit length.
  result.add(char(128 or opcode))
  if payload.len < 126: result.add(char(payload.len)) # Short canonical length.
  else: # Medium canonical length is in network order.
    result.add(char(126)); result.add(char(payload.len shr 8)); result.add(char(payload.len and 255))
  result.add(payload)

# Match a case-insensitive comma-delimited HTTP token without accepting substring matches.
proc hasToken(value, expected: string): bool =
  for token in value.split(','): # Header token lists may contain surrounding OWS.
    if token.strip().toLowerAscii() == expected: return true
  false

# Accept only a complete RFC 6455 version-13 upgrade at /, with no body or browser Origin.
# Empty output means invalid. SHA-1 is used solely for RFC 6455's public handshake challenge.
proc upgrade*(header: string): string =
  result = ""
  if header.len > MaxHeader or not header.endsWith("\r\n\r\n"): return
  let lines = header.split("\r\n")
  if lines.len < 3 or lines[0] != "GET / HTTP/1.1": return
  var key, connection, protocol, version, host = ""
  var seen: seq[string] = @[]
  for i in 1..<lines.len - 2: # Reject ambiguous duplicated headers and obsolete line folding.
    let line = lines[i]
    let colon = line.find(':')
    if colon < 1 or line[0] in {' ', '\t'}: return
    let name = line[0..<colon].toLowerAscii()
    for c in name: # HTTP field names are tokens; whitespace cannot disguise Origin or framing headers.
      if c notin {'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_',
          '`', '|', '~'}: return
    for c in line[colon + 1..^1]: # Bare CR/LF, NUL and other controls are not HTTP field values.
      if (ord(c) < 32 and c != '\t') or ord(c) == 127: return
    if name in seen: return
    seen.add(name)
    let value = line[colon + 1..^1].strip()
    case name
    of "sec-websocket-key": key = value # Exact canonical base64 challenge below.
    of "connection": connection = value # Upgrade must be a complete list token.
    of "upgrade": protocol = value # Only WebSocket is negotiated.
    of "sec-websocket-version": version = value # No legacy framing dialect.
    of "host": host = value # HTTP/1.1 requires a host.
    of "origin", "content-length", "transfer-encoding": return # Local tooling only; no request body.
    else: discard # Unknown extension/subprotocol offers are not negotiated.
  if host.len == 0 or version != "13" or not hasToken(connection, "upgrade") or
      protocol.toLowerAscii() != "websocket" or key.len != 24: return
  try: # The standard base64 decoder reports malformed input through its public error contract.
    let decoded = base64.decode(key)
    if decoded.len != 16 or base64.encode(decoded) != key: return
  except: return # Invalid challenge cannot produce a successful handshake.
  var hash = newSha1State()
  hash.update(key & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
  let digest = hash.finalize()
  result = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " &
      base64.encode(digest) & "\r\n\r\n"

# Parse outcome carries bytes only on success; incomplete and invalid frames expose no progress.
type
  FrameStatus* = enum incomplete, invalid, complete
  FrameResult* = object
    case state: FrameStatus
    of complete:
      body: string
      operation, length: int
      finished: bool
    else: discard

# Read the outcome before selecting success-only accessors.
func status*(value: FrameResult): FrameStatus = value.state
# Return an owned payload copy only after a complete frame has been established.
func payload*(value: FrameResult): string {.requires: value.state == complete.} = value.body
# Return the validated opcode on successful parsing.
func opcode*(value: FrameResult): int {.requires: value.state == complete.} = value.operation
# Return consumed bytes only for a complete frame.
func consumed*(value: FrameResult): int {.requires: value.state == complete.} = value.length
# Report FIN only after complete frame validation.
func final*(value: FrameResult): bool {.requires: value.state == complete.} = value.finished

# Decode one masked client frame, checking length before allocation; caller retains incomplete input.
proc decodeFrame*(input: string): FrameResult =
  if input.len < 2: return FrameResult(state: incomplete) # Wait for the fixed prefix.
  let first = ord(input[0])
  let second = ord(input[1])
  let opcode = first and 15
  if (first and 112) != 0 or (second and 128) == 0 or opcode notin [0, 1, 2, 8, 9, 10]:
    return FrameResult(state: invalid) # Extensions are not negotiated; all client frames are masked.
  var size = second and 127
  var start = 2
  if size == 127: return FrameResult(state: invalid) # Canonical 64-bit sizes exceed this endpoint's bound.
  if size == 126: # Read network-order medium lengths only after both bytes arrive.
    if input.len < 4: return FrameResult(state: incomplete)
    size = ord(input[2]) * 256 + ord(input[3]); start = 4
    if size < 126: return FrameResult(state: invalid)
  if size > MaxMessage or (opcode >= 8 and (size > 125 or (first and 128) == 0)):
    return FrameResult(state: invalid) # Control frames cannot be fragmented or oversized.
  if input.len < start + 4 + size: return FrameResult(state: incomplete)
  var payload = newString(size)
  for i in 0..<size: # The validated extent includes the mask and complete body.
    payload[i] = char(ord(input[start + 4 + i]) xor ord(input[start + i mod 4]))
  FrameResult(state: complete, body: move(payload), operation: opcode,
      length: start + 4 + size, finished: (first and 128) != 0)
