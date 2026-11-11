# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded RFC 6455 upgrade and frame decoding for loopback RPC.
##
## HTTP is the version-13 upgrade boundary. The peer dispatcher supplies the enabled
## UI port, which limits browser Origin to the matching IPv4 loopback or localhost
## origin. Nonbrowser clients can omit Origin. The decoder requires masked client
## frames and canonical lengths, returning owned bytes for message reassembly. The
## dispatcher validates text after reassembly so fragments can split a UTF-8 scalar.

import std/[strutils, base64, sha1]
import ../lib/utf8
import std/websocket as stock
import std/http/httpmsg as http_msg
import std/http/httpparse as http_parse
export utf8

const MaxMessage* = 16384
const MaxHeader* = http_parse.MaxHeadLen
const MaxClientFrameHeader* = 8 # Two base bytes, two length bytes and four mask bytes.

proc frame*(payload: string, opcode = 1): string =
  ## Produce one unmasked final server frame; caller supplies a bounded payload and valid opcode.
  if payload.len > 65535: return ""
  stock.frameHeader(stock.WsOpcode(opcode), payload.len, false, default(array[4, char])) & payload

proc hasToken(value, expected: string): bool =
  ## Match a case-insensitive comma-delimited HTTP token without accepting substring matches.
  for token in value.split(','): # Header token lists may contain surrounding OWS.
    if token.strip().toLowerAscii() == expected: return true
  false

proc upgrade*(header: string, uiPort: uint16 = 0, tags = http_msg.newHttpTags()): string =
  ## Accept a complete version-13 WebSocket upgrade at /, with no body and an optional exact UI browser Origin.
  ## Empty output means invalid. SHA-1 is used solely for RFC 6455's public handshake challenge.
  ## The stock request-head parser handles syntax. This routine owns Upgrade,
  ## endpoint, selector uniqueness and exact Origin policy.
  result = ""
  # Each handshake owns its parsed message until return. The listener reuses the vocabulary.
  var head = http_msg.initHttpMsg(tags)
  if http_parse.parseRequestHead(toOpenArray(header, 0, header.len - 1), head) != header.len: return
  if head.versionOf != http_msg.tag(http_msg.tV11): return # This endpoint uses the HTTP/1.1 Upgrade handshake.
  for field in ["host", "origin", "connection", "upgrade", "sec-websocket-key",
      "sec-websocket-version"]:
    if head.countHeaderByName(field) > 1: return # Handshake selectors cannot have conflicting values.
  if head.methodOf != http_msg.tag(http_msg.mGet) or head.target != "/": return
  if head.contains(http_msg.hContentLength) or head.contains(http_msg.hTransferEncoding): return
  let key = head.findHeader("sec-websocket-key")
  let connection = head.getStr(http_msg.hConnection)
  let protocol = head.getStr(http_msg.hUpgrade)
  let version = head.findHeader("sec-websocket-version")
  let host = head.getStr(http_msg.hHost)
  var origin = ""
  if head.contains(http_msg.hOrigin):
    # Browser origins remain an application allowlist checked before any upgrade response.
    let suffix = if uiPort == 80: "" else: ":" & $uiPort
    origin = head.getStr(http_msg.hOrigin)
    if uiPort == 0 or origin notin ["http://127.0.0.1" & suffix, "http://localhost" &
        suffix]: return
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
      base64.encode(digest) & "\r\n"
  if origin.len > 0: # Reflect only an exact allowlisted UI origin, never a wildcard.
    result.add("Access-Control-Allow-Origin: " & origin & "\r\nVary: Origin\r\n")
  result.add("\r\n")

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

func status*(value: FrameResult): FrameStatus =
  ## Read the outcome before selecting success-only accessors.
  value.state

func payload*(value: FrameResult): string {.requires: value.state == complete.} =
  ## Return an owned payload copy only after a complete frame has been established.
  value.body

func opcode*(value: FrameResult): int {.requires: value.state == complete.} =
  ## Return the validated opcode on successful parsing.
  value.operation

func consumed*(value: FrameResult): int {.requires: value.state == complete.} =
  ## Return consumed bytes only for a complete frame.
  value.length

func final*(value: FrameResult): bool {.requires: value.state == complete.} =
  ## Report FIN only after complete frame validation.
  value.finished

proc decodeFrame*(input: string): FrameResult =
  ## Decode one masked client frame, checking length before allocation; caller retains incomplete input.
  if input.len < 2: return FrameResult(state: incomplete)
  if (ord(input[0]) and 112) != 0 or (ord(input[1]) and 128) == 0 or
      (ord(input[1]) and 127) == 127:
    return FrameResult(state: invalid) # No extensions, unmasked input or 64-bit lengths.
  var header = default(stock.WsFrame)
  let start = stock.parseFrameHeader(toOpenArray(input, 0, input.len - 1), header)
  if start == http_parse.ParseIncomplete: return FrameResult(state: incomplete)
  if start < 0 or header.len > MaxMessage: return FrameResult(state: invalid)
  if input.len < start + header.len: return FrameResult(state: incomplete)
  var payload = ""
  if header.len > 0:
    # Mask through a bulk store so the string's inline prefix reflects the decoded bytes.
    let bytes = payload.beginStore(header.len)
    if bytes == nil:
      payload.endStore()
      return FrameResult(state: invalid)
    copyMem(bytes, input.readRawData(start), header.len)
    var body = toOpenArray(bytes, 0, header.len - 1)
    stock.applyMask(body, header.key)
    payload.endStore()
  FrameResult(state: complete, body: move(payload), operation: ord(header.opcode),
      length: start + header.len, finished: header.fin)
