# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private management JSON-RPC registry, deliberately independent of the public WS dispatcher.
## Input/output, nesting, tokens and batch count are bounded. No key material is serialized.

import ../lib/json/[reader as json_reader, writer as json_writer]
import ../lib/utf8
import ../version

const MaxManagementBody* = 8192 ## Bounded request and serialized reply, independent of WS budgets.

type ManagementInfo* = object ## Startup-only admin metadata; contains no live canonical owners or secrets.
  role*, socketPath*, chainPath*, databasePath*: string
  processId*, effectiveUser*: uint32
  stateEnabled*: bool
  resources*: JsonValue # Detached bounded observations, never a live storage/worker owner.

proc failure(id: string, code: int32, message: string): string =
  ## Only validated request IDs or the fixed null literal reach trustedJson.
  $jsonObject([("jsonrpc", json("2.0")), ("id", trustedJson(id)),
    ("error", jsonObject([("code", json(code)), ("message", json(message))]))])

proc clientInfo(info: ManagementInfo): JsonValue =
  ## Expose a small explicit admin schema; paths and process identity remain off public RPC.
  jsonObject([("version", json(AppVersion)), ("revision", json(AppRevision)),
    ("pid", json(info.processId)), ("effectiveUid", json(info.effectiveUser)),
    ("role", json(info.role)), ("managementSocket", json(info.socketPath)),
    ("chainPath", json(info.chainPath)), ("databasePath", json(info.databasePath)),
    ("stateEnabled", json(info.stateEnabled)), ("resources", info.resources)])

proc call(values: seq[JsonToken], root: int, info: ManagementInfo): string =
  ## Validate one envelope before lookup; valid notifications never emit replies.
  if values[root].kind != objectValue: return failure("null", -32600, "Invalid Request")
  var names: seq[string] = @[]
  var version, methodFound, hasId, invalid = false
  var methodName = ""
  var id = "null"
  var params = -1
  var index = root + 1
  while index < values[root].next:
    let name = values[index].text
    if name in names: return failure("null", -32600, "Invalid Request") # Ambiguous envelopes have no authority.
    names.add(name)
    inc index
    let token = values[index]
    case name
    of "jsonrpc": version = token.kind == stringValue and token.text == "2.0"
    of "method": methodFound = token.kind == stringValue; methodName = token.text
    of "params": params = index
    of "id":
      hasId = true
      if token.kind == stringValue: id = $json(token.text)
      elif token.kind == numberValue or (token.kind == literalValue and token.text == "null"):
        id = token.text # Never narrow or round a caller's numeric identifier.
      else: invalid = true
    else: discard # JSON-RPC permits extension envelope members.
    index = token.next
  if invalid or not version or not methodFound: return failure("null", -32600, "Invalid Request")
  if not hasId: return "" # This first read-only method has no notification side effects.
  if methodName != "ragnarok_unsafe_clientInfo": return failure(id, -32601, "Method not found")
  if params >= 0:
    let kind = values[params].kind
    if kind notin {arrayValue, objectValue} or values[params].next != params + 1:
      return failure(id, -32602, "Expected no parameters") # Both empty positional/named params are valid.
  $jsonObject([("jsonrpc", json("2.0")), ("id", trustedJson(id)), ("result", clientInfo(info))])

proc respond*(body: string, info: ManagementInfo): string =
  ## Empty output means notifications only; malformed input yields a bounded JSON-RPC error.
  if body.len == 0 or body.len > MaxManagementBody or not validUtf8(body):
    return failure("null", -32700, "Parse error")
  var values: seq[JsonToken] = @[]
  if not parseValues(body, values, 256, 8): return failure("null", -32700, "Parse error")
  if values[0].kind != arrayValue:
    let reply = call(values, 0, info)
    if reply.len > MaxManagementBody: return failure("null", -32600, "Response budget exceeded")
    return reply # A large configured path never escapes the single-response ceiling.
  if values[0].next == 1: return failure("null", -32600, "Invalid Request")
  var count = 0
  var index = 1
  var output = ""
  while index < values[0].next:
    if count == 16: return failure("null", -32600, "Too many requests") # Bound aggregate dispatch work.
    let reply = call(values, index, info)
    if reply.len > 0:
      if reply.len > MaxManagementBody - output.len - 3:
        return failure("null", -32600, "Response budget exceeded") # No partial batch is published.
      if output.len > 0: output.add(',') # Notifications do not create empty batch elements.
      output.add(reply)
    inc count
    index = values[index].next
  if output.len == 0: "" else: "[" & output & "]"
