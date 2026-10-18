## JSON-RPC 2.0 dispatch for the proof peer. No fabricated chain state or subscription success.
## Bounds: 16 KiB input, 16 levels, 2048 values and 16 requests per batch; no retained borrows.
import std/[strutils, parsejson, streams, parseutils]
import ./wire

const Platform = when defined(linux): "linux" elif defined(macosx): "macos" else: "unknown"
const Architecture = when defined(arm64): "arm64" elif defined(amd64): "amd64" else: "unknown"

# Flat parse tokens own decoded strings/raw numeric lexemes; next skips a complete subtree.
type
  Kind = enum objectValue, arrayValue, stringValue, numberValue, literalValue
  Value = object
    kind: Kind
    text: string
    next: int
  Parser = object
    text: string
    position: int
    values: seq[Value]
  # Caller supplies only observed public runtime information, copied synchronously during dispatch.
  ClientInfo* = object
    uptimeMs*: int64
    peers*: uint32
    role*: string
    port*: uint16
    occupiedBytes*, reservedBytes*: int

# JSON quoting preserves UTF-8 while escaping ASCII controls and delimiters.
proc quote*(text: string): string =
  result = "\""
  for c in text: # Every control character is escaped independently of its printable representation.
    if c == '"' or c == '\\': result.add('\\'); result.add(c)
    elif ord(c) < 32: result.add("\\u00" & toHex(ord(c), 2))
    else: result.add(c) # Valid UTF-8 is preserved byte-for-byte.
  result.add('"')

# Skip only the four whitespace bytes admitted by JSON.
proc whitespace(p: var Parser) =
  while p.position < p.text.len and p.text[p.position] in {' ', '\t', '\r', '\n'}:
    inc p.position # The length check precedes each byte read.

# Consume a bounded string with strict escape/surrogate syntax, then use the standard string decoder.
proc stringToken(p: var Parser, decoded: var string): bool =
  let start = p.position
  inc p.position
  while p.position < p.text.len: # Scan raw syntax before the standard decoder can normalize escapes.
    let c = p.text[p.position]
    inc p.position
    if c == '"': # The complete validated token is decoded in a short-lived owned stream.
      var parser = default(JsonParser)
      parser.open(newStringStream(p.text[start..<p.position]), "RPC string")
      defer: parser.close()
      parser.next()
      if parser.kind != jsonString: return false
      decoded = parser.str
      return validUtf8(decoded)
    if ord(c) < 32: return false # Literal controls are invalid even inside strings.
    if c == '\\': # Escapes require their complete spelling before any conversion.
      if p.position >= p.text.len: return false
      let escape = p.text[p.position]
      inc p.position
      if escape == 'u':
        if p.text.len - p.position < 4: return false
        let hex = p.text[p.position..<p.position + 4]
        for digit in hex: # Hex decoding only follows exact digit validation.
          if digit notin HexDigits: return false
        var code = 0
        discard parseHex(hex, code)
        p.position += 4
        if code in 0xdc00..0xdfff: return false # A low surrogate needs a preceding high surrogate.
        if code in 0xd800..0xdbff: # A high surrogate requires one escaped low surrogate.
          if p.text.len - p.position < 6 or p.text[p.position..<p.position + 2] !=
              "\\u": return false
          let low = p.text[p.position + 2..<p.position + 6]
          for digit in low:
            if digit notin HexDigits: return false # Never parse unvalidated digits.
          var lowCode = 0
          discard parseHex(low, lowCode)
          if lowCode notin 0xdc00..0xdfff: return false
          p.position += 6
      elif escape notin {'"', '\\', '/', 'b', 'f', 'n', 'r', 't'}: return false # No non-JSON escape aliases.
  false

# Parse exactly one subtree with bounded recursion; failure discards the entire private parse owner.
proc value(p: var Parser, depth: int): bool =
  p.whitespace()
  if depth > 16 or p.values.len >= 2048 or p.position >= p.text.len: return false
  let index = p.values.len
  p.values.add(Value(kind: literalValue, text: "", next: 0))
  let first = p.text[p.position]
  if first in {'{', '['}: # Containers preserve key/value order, including duplicate keys for dispatch rejection.
    let isObject = first == '{'
    let closing = if isObject: '}' else: ']'
    p.values[index].kind = if isObject: objectValue else: arrayValue
    inc p.position
    p.whitespace()
    if p.position < p.text.len and p.text[p.position] ==
        closing: inc p.position # Empty containers are valid JSON.
    else:
      while true: # Every child consumes input; size/depth bounds cap total parsing work.
        if isObject:
          if p.position >= p.text.len or p.text[p.position] != '"': return false # Object keys must be strings.
          if not p.value(depth + 1): return false
          p.whitespace()
          if p.position >= p.text.len or p.text[p.position] != ':': return false
          inc p.position
        if not p.value(depth + 1): return false
        p.whitespace()
        if p.position >= p.text.len: return false
        if p.text[p.position] == closing: inc p.position; break # Complete container.
        if p.text[p.position] != ',': return false
        inc p.position
        p.whitespace() # A trailing comma reaches value/key parsing and is rejected.
  elif first == '"': # Decode keys and string IDs without retaining source spans.
    p.values[index].kind = stringValue
    var decoded = ""
    if not p.stringToken(decoded): return false
    p.values[index].text = move(decoded)
  else: # Validate numeric grammar explicitly and preserve IDs without float/int narrowing.
    let start = p.position
    while p.position < p.text.len and p.text[p.position] notin {' ', '\t', '\r', '\n', ',', ']', '}'}:
      inc p.position # Token extent is bounded by the original input limit.
    let token = p.text[start..<p.position]
    if token notin ["true", "false", "null"]:
      var i = 0
      if token.len > 0 and token[0] == '-': inc i # Optional leading minus only.
      if i >= token.len: return false
      if token[i] == '0': inc i # Leading zero cannot absorb further integer digits.
      elif token[i] in {'1'..'9'}:
        while i < token.len and token[i] in {'0'..'9'}: inc i # Nonzero integer part.
      else: return false
      if i < token.len and token[i] == '.': # Fraction requires at least one digit.
        inc i
        let begin = i
        while i < token.len and token[i] in {'0'..'9'}: inc i
        if i == begin: return false
      if i < token.len and token[i] in {'e', 'E'}: # Exponent requires digits after its optional sign.
        inc i
        if i < token.len and token[i] in {'+', '-'}: inc i
        let begin = i
        while i < token.len and token[i] in {'0'..'9'}: inc i
        if i == begin: return false
      if i != token.len: return false
      p.values[index].kind = numberValue
    p.values[index].text = token
  p.values[index].next = p.values.len
  true

# Construct a JSON-RPC error; id is already a validated JSON scalar, never arbitrary caller text.
proc error(id: string, code: int, message: string): string =
  "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":" & $code & ",\"message\":" & quote(
      message) & "}}"

# Describe only implemented capabilities; absent chain/backend data is explicit rather than guessed.
proc clientInfo(info: ClientInfo): string =
  "{\"name\":\"Ragnarok\",\"version\":\"development\",\"implementation\":\"Nimony\",\"compilerVersion\":\"0.6.3\",\"grayPaperVersion\":\"0.8.0\",\"os\":" &
      quote(Platform) &
    ",\"architecture\":" & quote(Architecture) & ",\"role\":" & quote(info.role) &
    ",\"uptimeMs\":" & $info.uptimeMs & ",\"connectedPeers\":" & $info.peers &
    ",\"memory\":{\"occupiedBytes\":" & $info.occupiedBytes & ",\"reservedBytes\":" &
        $info.reservedBytes &
        "},\"chain\":null,\"bestBlock\":null,\"finalizedBlock\":null,\"rpc\":{\"transport\":\"websocket\",\"address\":\"127.0.0.1\",\"port\":" &$info.port &
    ",\"methods\":[\"ragnarok_clientInfo\"],\"subscriptions\":false,\"maxMessageBytes\":16384,\"maxBatchRequests\":16}}"

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
  if methodName == "ragnarok_clientInfo":
    if parameters >= 0 and values[parameters].next != parameters + 1: return error(id, -32602, "Expected no parameters")
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & clientInfo(info) & "}"
  error(id, -32601, "Method not available") # Chain queries/subscriptions are unavailable until backed by actual state.

# Parse and execute one whole message atomically; empty output means a notification-only message.
proc respond*(text: string, info: ClientInfo): string =
  if text.len == 0 or text.len > MaxMessage or not validUtf8(text): return error("null", -32700, "Parse error")
  var parser = Parser(text: text, position: 0, values: @[])
  if not parser.value(0): return error("null", -32700, "Parse error")
  parser.whitespace()
  if parser.position != text.len: return error("null", -32700, "Parse error")
  if parser.values[0].kind != arrayValue: return dispatch(parser.values, 0, info)
  var count = 0
  var i = 1
  while i < parser.values.len: # Count before executing any member of an oversized batch.
    inc count
    i = parser.values[i].next
  if count == 0 or count > 16: return error("null", -32600, "Invalid batch size")
  result = ""
  i = 1
  while i < parser.values.len: # At most 16 bounded responses fit the server output policy.
    let response = dispatch(parser.values, i, info)
    if response.len > 0:
      if result.len > 0: result.add(',') # Notifications contribute no array entry.
      result.add(response)
    i = parser.values[i].next
  if result.len > 0: result = "[" & result & "]" # Notification-only batches produce no frame.
