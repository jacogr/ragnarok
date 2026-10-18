# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JSON-RPC 2.0 dispatch for the proof peer, including configured chain parameters.
## Bounds: 16 KiB input, 16 levels, 2048 values and 16 requests per batch; no retained borrows.
##
## Exposes JSON string quoting and respond for the supported JSON-RPC methods and protocol error
## responses. configuredParameters validates bounded chainspec text into an owned snapshot;
## parameters() includes four documented zero placeholders pending live-state derivation.

import std/[strutils, parsejson, streams]
import ./wire
import ../chain/parameters

const Platform = when defined(linux): "linux" elif defined(macosx): "macos" else: "unknown"
const Architecture = when defined(arm64): "arm64" elif defined(amd64): "amd64" else: "unknown"

# Flat parse tokens own decoded strings/raw numeric lexemes; next skips a complete subtree.
type
  Kind = enum objectValue, arrayValue, stringValue, numberValue, literalValue
  Value = object
    kind: Kind
    text: string
    next: int
  # Open containers retain only their token index and child count; depth is capped before growth.
  Container = object
    index: int
    children: int
  # Caller supplies only observed public runtime information, copied synchronously during dispatch.
  ClientInfo* = object
    uptimeMs*: int64
    peers*: uint32
    role*: string
    port*: uint16
    occupiedBytes*, reservedBytes*: int
    parameters*: ParameterResult # Optional immutable startup configuration; never read from disk per request.

# JSON quoting preserves UTF-8 while escaping ASCII controls and delimiters.
proc quote*(text: string): string =
  result = "\""
  for c in text: # Every control character is escaped independently of its printable representation.
    if c == '"' or c == '\\': result.add('\\'); result.add(c)
    elif ord(c) < 32: result.add("\\u00" & toHex(ord(c), 2))
    else: result.add(c) # Valid UTF-8 is preserved byte-for-byte.
  result.add('"')

# Reject lexical extensions accepted by the pinned stdlib; structure and decoding belong to JsonParser.
# This allocation-free pass does not parse values. Its input is already size-limited and valid UTF-8.
proc strictLexemes(text: string): bool =
  var quoted = false
  var escaped = false
  var previous = ' '
  for c in text: # Inspect raw bytes before the stdlib can normalize permissive spellings.
    if quoted:
      if ord(c) < 32: return false # JSON strings cannot contain literal controls.
      if escaped:
        if c notin {'"', '\\', '/', 'b', 'f', 'n', 'r', 't', 'u'}: return false
        escaped = false # Hex digits and surrogate pairs are checked by the standard decoder.
      elif c == '\\': escaped = true
      elif c == '"': quoted = false
      else: discard # Ordinary UTF-8 string bytes need no additional lexical policy.
    else:
      if c in {' ', '\t', '\r', '\n'}: continue # Only JSON whitespace may separate tokens.
      if ord(c) < 32 or c in {'/', '\'', '\\'}: return false # Exclude comments and non-JSON quotes.
      if c in {']', '}'} and previous == ',': return false # Stdlib accepts trailing commas.
      if c == '.' and previous notin {'0'..'9'}: return false # Stdlib normalizes .1 to 0.1.
      if c == '"': quoted = true
      previous = c
  not quoted and not escaped

# Validate a stdlib numeric lexeme without converting or narrowing the request ID.
proc strictNumber(token: string): bool =
  var i = 0
  if token.len > 0 and token[0] == '-': inc i # JSON permits only a leading minus.
  if i >= token.len: return false
  if token[i] == '0': inc i # A zero integer part cannot have more digits.
  elif token[i] in {'1'..'9'}:
    while i < token.len and token[i] in {'0'..'9'}: inc i # Consume the integer part.
  else: return false
  if i < token.len and token[i] == '.': # Fractions need at least one digit.
    inc i
    let begin = i
    while i < token.len and token[i] in {'0'..'9'}: inc i
    if i == begin: return false
  if i < token.len and token[i] in {'e', 'E'}: # Exponents need digits after any sign.
    inc i
    if i < token.len and token[i] in {'+', '-'}: inc i
    let begin = i
    while i < token.len and token[i] in {'0'..'9'}: inc i
    if i == begin: return false
  i == token.len

# Adapt standard streaming events to owned dispatch values; failure discards all partial output.
# The stdlib handles delimiters, separators, decoding and syntax errors. We cap its stack growth
# between events, enforce string object keys and preserve numeric text rather than using getInt/getFloat.
proc parseValues(text: string, values: var seq[Value], maxValues = 2048, maxDepth = 16): bool =
  if not strictLexemes(text): return false
  var parser = default(JsonParser)
  parser.open(newStringStream(text), "RPC request")
  defer: parser.close()
  var containers: seq[Container] = @[]
  while true: # One event at a time bounds allocations before the next stdlib parser step.
    parser.next()
    if parser.hasError or parser.kind == jsonError: return false
    case parser.kind
    of jsonEof: return values.len > 0 and containers.len == 0
    of jsonObjectEnd, jsonArrayEnd:
      if containers.len == 0: return false # Never access an absent open container.
      let parent = containers.pop()
      values[parent.index].next = values.len
    else:
      if values.len >= maxValues or containers.len >= maxDepth: return false
      if containers.len == 0:
        if values.len > 0: return false # Stdlib permits another root after a closed container.
      else:
        let parent = containers.len - 1
        if values[containers[parent].index].kind == objectValue and
            containers[parent].children mod 2 == 0 and parser.kind != jsonString:
          return false # The streaming parser also accepts non-string object keys.
        inc containers[parent].children
      var token = Value(kind: literalValue, text: "", next: values.len + 1)
      case parser.kind
      of jsonString:
        token.kind = stringValue
        token.text = parser.str
        if not validUtf8(token.text): return false # Reject lone low surrogates from the decoder.
      of jsonInt, jsonFloat:
        token.kind = numberValue
        token.text = parser.str
        if not strictNumber(token.text): return false
      of jsonObjectStart: token.kind = objectValue
      of jsonArrayStart: token.kind = arrayValue
      of jsonTrue: token.text = "true"
      of jsonFalse: token.text = "false"
      of jsonNull: token.text = "null"
      else: return false # Error, EOF and closing events have already been handled.
      values.add(move(token))
      if parser.kind in {jsonObjectStart, jsonArrayStart}:
        containers.add(Container(index: values.len - 1, children: 0)) # Bounded open-container stack.

# Extract one strict JIP-4 parameter field from a bounded startup file. Genesis data is not imported.
# Unknown fields are parsed for syntax only; duplicate root members and missing parameters fail atomically.
proc configuredParameters*(text: string): ParameterResult =
  if text.len == 0 or text.len > 8 * 1024 * 1024 or not validUtf8(text):
    return default(ParameterResult) # Missing, oversized or invalid text cannot imply a default chain.
  var values: seq[Value] = @[]
  if not parseValues(text, values, 262144, 32) or values[0].kind != objectValue:
    return default(ParameterResult)
  var found = false
  var encoded = ""
  var keys: seq[string] = @[]
  var i = 1
  while i < values[0].next: # Object events alternate decoded string keys and complete value subtrees.
    let key = values[i].text
    if keys.len >= 64 or key in keys: return default(ParameterResult) # Duplicate configuration is ambiguous.
    keys.add(key)
    inc i
    if key == "protocol_parameters":
      if values[i].kind != stringValue: return default(ParameterResult)
      found = true
      encoded = values[i].text
    i = values[i].next
  if not found: return default(ParameterResult)
  decodeParametersHex(encoded)

# Map the immutable GP fetch tuple to JIP-2 V1 without machine signed/float conversions.
# The four live-state fields remain explicit zero placeholders until their derivation is implemented.
proc parameterObject(parameters: Parameters): string =
  const Names: array[Parameter, string] = [
    "deposit_per_item", "deposit_per_byte", "deposit_per_account", "core_count",
    "min_turnaround_period", "epoch_period", "max_accumulate_gas", "max_is_authorized_gas",
    "max_refine_gas", "block_gas_limit", "recent_block_count", "max_work_items",
    "max_dependencies", "max_tickets_per_block", "max_lookup_anchor_age", "auth_window",
    "slot_period_sec", "auth_queue_len", "rotation_period", "max_extrinsics",
    "availability_timeout", "max_authorizer_code_size", "max_input", "max_service_code_size",
    "max_imports", "max_report_elective_data", "transfer_memo_size", "max_exports", "epoch_tail_start"]
  result = "{\"V1\":{"
  for field in low(Parameter)..high(Parameter): # Width-limited uint64 values serialize as exact decimal Numbers.
    if field != low(Parameter): result.add(',')
    result.add(quote(Names[field]) & ":" & $parameters.get(field))
  result.add(",\"tickets_attempts_number\":0,\"val_count\":0")
  result.add(",\"basic_piece_len\":0,\"segment_piece_count\":0}}")

# Construct a JSON-RPC error; id is already a validated JSON scalar, never arbitrary caller text.
proc error(id: string, code: int, message: string): string =
  "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":" & $code & ",\"message\":" & quote(
      message) & "}}"

# Describe only implemented capabilities; absent chain/backend data is explicit rather than guessed.
proc clientInfo(info: ClientInfo): string =
  result = "{\"name\":\"Ragnarok\",\"version\":\"development\",\"implementation\":\"Nimony\""
  result.add(",\"compilerVersion\":\"0.6.3\",\"grayPaperVersion\":\"0.8.0\"")
  result.add(",\"os\":" & quote(Platform) & ",\"architecture\":" & quote(Architecture))
  result.add(",\"role\":" & quote(info.role) & ",\"uptimeMs\":" & $info.uptimeMs)
  result.add(",\"connectedPeers\":" & $info.peers)
  result.add(",\"memory\":{\"occupiedBytes\":" & $info.occupiedBytes)
  result.add(",\"reservedBytes\":" & $info.reservedBytes & "}")
  result.add(",\"chain\":null,\"bestBlock\":null,\"finalizedBlock\":null")
  result.add(",\"rpc\":{\"transport\":\"websocket\",\"address\":\"127.0.0.1\"")
  result.add(",\"port\":" & $info.port & ",\"methods\":[\"ragnarok_clientInfo\",\"parameters\"]")
  result.add(",\"subscriptions\":false,\"maxMessageBytes\":16384,\"maxBatchRequests\":16}}")

# Validate an envelope independently of execution. Invalid requests reply with null IDs; notifications are silent.
proc dispatch(values: seq[Value], start: int, info: ClientInfo): string =
  if values[start].kind != objectValue: return error("null", -32600, "Invalid Request")
  var id = "null"
  var hasId, version, methodFound, invalid = false
  var methodName = ""
  var parameters = -1
  var seen: seq[string] = @[]
  var i = start + 1
  while i < values[start].next: # Object parser guarantees alternating string keys and complete values.
    let key = values[i].text
    inc i
    if key in seen: invalid = true # Duplicate envelope members are ambiguous, even extension members.
    seen.add(key)
    let token = values[i]
    case key
    of "jsonrpc": version = token.kind == stringValue and token.text == "2.0"
    of "method": methodFound = token.kind == stringValue; methodName = token.text
    of "params": parameters = i # Method validation enforces JIP-2's positional convention below.
    of "id":
      hasId = true
      if token.kind == stringValue: id = quote(token.text) # Preserve decoded string IDs.
      elif token.kind == numberValue or (token.kind == literalValue and token.text ==
          "null"): id = token.text
      else: invalid = true # Booleans and containers cannot identify JSON-RPC calls.
    else: discard # JSON-RPC permits additional envelope members.
    i = token.next
  if invalid or not version or not methodFound: return error("null", -32600, "Invalid Request")
  if not hasId: return "" # This read-only dispatch has no notification side effects.
  if parameters >= 0 and values[parameters].kind != arrayValue: return error(id, -32602, "Expected positional params")
  if methodName in ["ragnarok_clientInfo", "parameters"]:
    if parameters >= 0 and values[parameters].next != parameters + 1: return error(id, -32602, "Expected no parameters")
    if methodName == "parameters":
      if not info.parameters.ok: return error(id, 0, "Chain parameters unavailable; configure --chain")
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & parameterObject(
          info.parameters.value) & "}"
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & clientInfo(info) & "}"
  error(id, -32601, "Method not available") # Chain queries/subscriptions are unavailable until backed by actual state.

# Parse and execute one whole message atomically; empty output means a notification-only message.
proc respond*(text: string, info: ClientInfo): string =
  if text.len == 0 or text.len > MaxMessage or not validUtf8(text): return error("null", -32700, "Parse error")
  var values: seq[Value] = @[]
  if not parseValues(text, values): return error("null", -32700, "Parse error")
  if values[0].kind != arrayValue: return dispatch(values, 0, info)
  var count = 0
  var i = 1
  while i < values.len: # Count before executing any member of an oversized batch.
    inc count
    i = values[i].next
  if count == 0 or count > 16: return error("null", -32600, "Invalid batch size")
  result = ""
  i = 1
  while i < values.len: # At most 16 bounded responses fit the server output policy.
    let response = dispatch(values, i, info)
    if response.len > 0:
      if result.len > 0: result.add(',') # Notifications contribute no array entry.
      result.add(response)
    i = values[i].next
  if result.len > 0: result = "[" & result & "]" # Notification-only batches produce no frame.
