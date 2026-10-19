# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JSON-RPC 2.0 dispatch for configured parameters and immutable provider-backed chain/service queries.
## Bounds: 16 KiB input, 16 levels, 2048 values, 16 requests and 65,535 output bytes; no retained borrows.
##
## Exposes JSON string quoting and respond for the supported JSON-RPC methods and protocol error
## responses. configuredParameters and configuredGenesis validate bounded chainspec text into
## owned parameter and genesis snapshots;
## parameters() derives active-roster erasure geometry and pending-roster ticket limits;
## missing state uses zero.

import std/[strutils, parsejson, streams, base64]
import ./wire
import ../chain/[parameters, genesis, services, statistics, beefy, reports, provider]
import ../codec/[state_trie, state_layout, header]
import ../state/store

const MaxReplyBytes = 65535 # One canonical medium-length WS frame, including batch punctuation.
const MaxBlobReplyBytes = 32768 # Bound each raw value copy/hash before Base64 encoding.
const ReplyBudgetError = "RPC response exceeds configured output budget"

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
    chain*: ChainView # Immutable request view; the initial adapter retains configured genesis.
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

# Decode bounded, unprefixed hex atomically; an empty value is valid only for state values.
proc decodeHex(text: string, maximum: int, output: var seq[byte]): bool =
  if text.len mod 2 != 0 or text.len div 2 > maximum: return false # Bound before allocation.
  var bytes = newSeq[byte](text.len div 2)
  # Each pair has exactly two hexadecimal digits, excluding prefixes and separators.
  for i in 0..<bytes.len:
    var value = 0
    # Accumulate exactly two nibbles so narrowing to a byte is proved safe.
    for j in 0..<2:
      let c = text[2 * i + j]
      if c notin HexDigits: return false # Invalid input publishes no partial bytes.
      value = value * 16 + (if c <= '9': ord(c) - ord('0') else: ord(c.toLowerAscii) - ord('a') + 10)
    bytes[i] = byte(value)
  output = move(bytes)
  true

# Import an optional complete genesis pair using the same strict bounded JSON policy as parameters.
proc configuredGenesis*(text: string, parameters: Parameters): GenesisResult =
  # Reject absent, oversized or non-UTF-8 input before token allocation.
  if text.len == 0 or text.len > 8 * 1024 * 1024 or not validUtf8(text): return invalidGenesis()
  var values: seq[Value] = @[]
  # Only a complete strict JSON object can describe a chainspec.
  if not parseValues(text, values, 262144, 32) or values[0].kind !=
      objectValue: return invalidGenesis()
  var headerIndex = -1
  var stateIndex = -1
  var keys: seq[string] = @[]
  var i = 1
  # Root duplicates are ambiguous even when they name fields this slice does not consume.
  while i < values[0].next:
    let key = values[i].text
    if keys.len >= 64 or key in keys: return invalidGenesis() # Bound metadata and reject ambiguous duplicates.
    keys.add(key)
    inc i
    if key == "genesis_header": headerIndex = i # Record positions only after syntax validation.
    elif key == "genesis_state": stateIndex = i # State entries are decoded below.
    i = values[i].next
  if headerIndex < 0 and stateIndex < 0: return unavailableGenesis() # Parameters-only configuration remains supported.
  if headerIndex < 0 or stateIndex < 0: return invalidGenesis() # An explicit pair must be complete.
  # The header is one encoded blob and state is a serialized key/value object.
  if values[headerIndex].kind != stringValue or values[stateIndex].kind !=
      objectValue: return invalidGenesis()
  var wire: seq[byte] = @[]
  if not decodeHex(values[headerIndex].text, 256 * 1024, wire): return invalidGenesis() # Bound the header before decoding.
  var entries: seq[StateEntry] = @[]
  var total = 0
  i = stateIndex + 1
  # Decode map keys and values under independent count and byte budgets before retaining them.
  while i < values[stateIndex].next:
    if entries.len >= 16384 or values[i].text.len != 62: return invalidGenesis() # Every serialized key has exactly 31 bytes.
    var keyBytes, data: seq[byte] = @[]
    if not decodeHex(values[i].text, 31, keyBytes): return invalidGenesis() # Reject non-hex key encodings.
    inc i
    if values[i].kind != stringValue or not decodeHex(values[i].text, 4 * 1024 * 1024 - total, data):
      return invalidGenesis() # Nested and non-string state values are not serialized state.
    total += data.len
    var key = default(array[31, byte])
    for j in 0..<31: key[j] = keyBytes[j] # Exact decoded key width was proved above.
    entries.add(StateEntry(key: StateKey(key), value: move(data)))
    i = values[i].next
  captureGenesis(wire, entries, parameters)

# JIP-2 hash strings are canonical padded Base64, preserving exactly 32 bytes.
proc validHash(text: string): bool =
  if text.len != 44 or text[43] != '=': return false # Exact shape bounds decoder work.
  for i in 0..<43:
    if text[i] notin {'A'..'Z', 'a'..'z', '0'..'9', '+',
        '/'}: return false # No alternate alphabets or whitespace.
  let decoded = base64.decode(text)
  decoded.len == 32 and base64.encode(decoded) == text

# Decode canonical padded Base64, including the empty blob, with a pre-allocation byte ceiling.
proc decodeBlob(text: string, maximum: int, output: var seq[byte]): bool =
  if text.len mod 4 != 0 or text.len > ((maximum + 2) div 3) * 4:
    return false # Bound work before calling the standard decoder.
  var padding = 0
  if text.len > 0 and text[^1] == '=': inc padding # A single trailing pad may complete two bytes.
  if text.len > 1 and text[^2] == '=': inc padding # Two pads may complete one byte.
  # Every non-padding byte must use the RFC 4648 alphabet, with no whitespace or URL-safe variant.
  for i in 0..<text.len - padding:
    if text[i] notin {'A'..'Z', 'a'..'z', '0'..'9', '+', '/'}: return false
  let decoded = base64.decode(text)
  if decoded.len > maximum or base64.encode(decoded) != text:
    return false # Re-encoding rejects nonzero pad bits and incomplete/noncanonical spellings.
  output = newSeq[byte](decoded.len)
  for i in 0..<decoded.len: output[i] = byte(decoded[i]) # Publish only complete, validated bytes.
  true

# Parse a JSON integer token without signed conversion, floating point or overflow.
proc serviceNumber(token: Value, output: var uint32): bool =
  if token.kind != numberValue or token.text.len == 0: return false # IDs require an integer token.
  var number = 0'u32
  # Before each multiply/add, prove the next unsigned-32-bit result remains representable.
  for c in token.text:
    if c notin {'0'..'9'}: return false # Negative, fractional and exponent spellings are not service IDs.
    let digit = uint32(ord(c) - ord('0'))
    if number > (high(uint32) - digit) div 10: return false # No wrapping or narrowing of oversized IDs.
    number = number * 10 + digit
  output = number
  true

# Render a copied genesis descriptor using JIP-2's Base64 identity and numeric slot.
proc descriptor(value: Genesis): string =
  "{\"header_hash\":" & quote(base64.encode(array[32, byte](value.blockHash))) & ",\"slot\":" &
      $value.slot & "}"

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

## Resolve a canonical wire identity through the provider; wire validation never leaks into chain code.
proc resolveBlock(chain: ChainView, text: string, parent = false): GenesisResult =
  var bytes: seq[byte] = @[]
  if not decodeBlob(text, 32, bytes) or bytes.len != 32:
    return unavailableGenesis() # Defensive rejection keeps the typed lookup independent of caller validation.
  var identity = default(array[32, byte])
  for index in 0..<32:
    identity[index] = bytes[index] # Exact width was established before copying.
  if parent:
    return chain.parentOf(BlockHash(identity)) # Parent descriptors require retained provider evidence.
  chain.blockAt(BlockHash(identity))

# Map the immutable GP fetch tuple to JIP-2 V1 without machine signed/float conversions.
# Captured C(8)/C(4) supply population, erasure geometry and ticket attempts; missing state uses zero.
proc parameterObject(parameters: Parameters, genesis: GenesisResult): string =
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
  var validators = 0
  var attempts = 0'u64
  var pieceBytes = 0'u64
  var pieces = 0'u64
  if genesis.error == GenesisError.None:
    validators = int(genesis.value.activeValidators) # Extract only the validated immutable owner.
    attempts = uint64(genesis.value.ticketAttempts)
    pieceBytes = uint64(genesis.value.basicPieceLength)
    pieces = uint64(genesis.value.segmentPieces)
  result.add(",\"tickets_attempts_number\":" & $attempts & ",\"val_count\":" & $validators)
  result.add(",\"basic_piece_len\":" & $pieceBytes & ",\"segment_piece_count\":" & $pieces & "}}")

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
  result.add(",\"chain\":null,\"bestBlock\":" & (if info.chain.bestBlock.error ==
      GenesisError.None: descriptor(info.chain.bestBlock.value) else: "null") & ",\"finalizedBlock\":null")
  result.add(",\"rpc\":{\"transport\":\"websocket\",\"address\":\"127.0.0.1\"")
  result.add(",\"port\":" & $info.port & ",\"methods\":[\"ragnarok_clientInfo\",\"parameters\",\"bestBlock\",\"parent\",\"stateRoot\",\"serviceData\",\"serviceValue\",\"servicePreimage\",\"serviceRequest\",\"statistics\",\"listServices\",\"beefyRoot\",\"workReport\",\"ragnarok_stateValue\",\"ragnarok_stateKeys\",\"ragnarok_header\"]")
  result.add(",\"subscriptions\":false,\"maxMessageBytes\":16384,\"maxBatchRequests\":16}}")

# Validate an envelope independently of execution. Invalid requests reply with null IDs; notifications are silent.
proc dispatchImpl(values: seq[Value], start: int, info: ClientInfo, allowance: int): string =
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
  if methodName == "ragnarok_stateKeys":
    if parameters < 0: return error(id, -32602, "Expected hash, cursor and count") # All pagination arguments are explicit.
    let argument = parameters + 1
    if values[parameters].next != argument + 3 or values[argument].kind != stringValue:
      return error(id, -32602, "Expected hash, cursor and count") # Exactly three scalar arguments.
    let hash = values[argument].text
    if not validHash(hash): return error(id, -32602,
        "Expected padded Base64 hash") # Resolve only canonical identities.
    let cursor = values[argument + 1]
    let fromStart = cursor.kind == literalValue and cursor.text == "null"
    var keyBytes: seq[byte] = @[]
    if not fromStart:
      # Null begins enumeration; all other cursors must encode an exact serialized key.
      if cursor.kind != stringValue or not decodeBlob(cursor.text, 31, keyBytes) or keyBytes.len != 31:
        return error(id, -32602, "Expected null or padded Base64 31-byte cursor")
    var count = 0'u32
    if not serviceNumber(values[argument + 2], count) or count == 0 or count > 128:
      return error(id, -32602, "Expected count from 1 to 128") # Bound work and JSON growth before lookup.
    let selected = resolveBlock(info.chain, hash)
    if selected.error == GenesisError.None:
      # Each page is bound to the requested immutable block, never a moving implicit head.
      let view = selected.value
      var start = 0
      if not fromStart:
        # Exact cursor bytes locate an exclusive upper bound without scanning prior keys.
        var key = default(array[31, byte])
        for index in 0..<31: key[index] = keyBytes[index] # Decoding proved the complete extent.
        start = int(view.keyAfter(StateKey(key)))
      let finish = start + min(int(count), view.keyCount - start)
      var keys = "["
      var last = "null"
      let budget = max(0, allowance - id.len - 256)
      for index in start..<finish:
        # Encode fixed key copies only; enumeration never reads or copies state values.
        let encoded = quote(base64.encode(array[31, byte](view.keyAt(StateKeyIndex(index)))))
        if keys.len + encoded.len + 2 > budget:
          return error(id, 0, ReplyBudgetError) # No misleading partial page or skipped continuation.
        if index > start: keys.add(',') # Separate keys after the first item.
        keys.add(encoded)
        last = encoded
      keys.add(']')
      if finish == view.keyCount: last = "null" # No continuation when the end was reached exactly.
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":{\"keys\":" & keys &
          ",\"next\":" & last & "}}"
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":1,\"message\":\"Block unavailable\",\"data\":" &
        quote(hash) & "}}"
  if methodName == "ragnarok_stateValue":
    if parameters < 0: return error(id, -32602, "Expected header hash and state key") # Both identities are mandatory.
    let argument = parameters + 1
    if values[parameters].next != argument + 2 or values[argument].kind != stringValue or
        values[argument + 1].kind != stringValue:
      return error(id, -32602, "Expected header hash and state key") # No nested or extra arguments.
    let hash = values[argument].text
    if not validHash(hash): return error(id, -32602,
        "Expected padded Base64 hash") # Validate before state lookup.
    var keyBytes: seq[byte] = @[]
    if not decodeBlob(values[argument + 1].text, 31, keyBytes) or keyBytes.len != 31:
      return error(id, -32602, "Expected padded Base64 31-byte state key") # Full serialized state keys, not service storage keys.
    let selected = resolveBlock(info.chain, hash)
    if selected.error == GenesisError.None:
      # Resolve the block before distinguishing missing and present entries.
      let view = selected.value
      var key = default(array[31, byte])
      for index in 0..<31: key[index] = keyBytes[index] # Exact key width was proved above.
      let found = view.lookup(StateKey(key))
      if found.error == StateStoreError.MissingKey:
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id &
            ",\"result\":null}" # Missing differs from a present empty blob.
      if found.error != StateStoreError.None:
        return error(id, 0, "Unreadable state value") # Failed owners never expose bytes.
      let budget = min(MaxBlobReplyBytes, max(0, (allowance - id.len - 256) div 4 * 3))
      if found.value.byteLength > budget:
        return error(id, 0, ReplyBudgetError) # Reject before copying or Base64 allocation.
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(
          found.value.bytes)) & "}"
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":1,\"message\":\"Block unavailable\",\"data\":" &
        quote(hash) & "}}"
  if methodName == "workReport":
    if parameters < 0: return error(id, -32602, "Expected one report hash") # Hash is mandatory.
    let argument = parameters + 1
    if values[parameters].next != argument + 1 or values[argument].kind != stringValue:
      return error(id, -32602, "Expected one report hash") # Only one positional scalar is accepted.
    let hash = values[argument].text
    if not validHash(hash): return error(id, -32602, "Expected padded Base64 hash") # Check before decoding.
    if info.chain.bestBlock.error == GenesisError.None:
      # Search the immutable configured assignments under the shared response budget.
      let raw = base64.decode(hash)
      var identity = default(array[32, byte])
      for index in 0..<32: identity[index] = byte(raw[index]) # Canonical hash validation proved the extent.
      let budget = ByteLimit(min(MaxBlobReplyBytes, max(0, (allowance - id.len - 256) div 4 * 3)))
      let found = info.chain.reportAt(WorkReportHash(identity), budget)
      if found.error == ReportReadError.None:
        # Retain the report owner while copying its complete canonical bytes for Base64.
        let metadata = ownedReportInfo(found.value)
        if metadata.error != OwnershipError.None: return error(id, 0,
            "Invalid report owner") # No default payload access.
        var bytes = newSeq[byte](metadata.value.consumed)
        if encodeOwnedReport(found.value, bytes).error != OwnershipError.None:
          return error(id, 0, "Invalid report owner") # Never publish a partial re-encoding.
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(bytes)) & "}"
      if found.error == ReportReadError.LimitExceeded:
        return error(id, 0, ReplyBudgetError) # Bounded lookup or reply refused; no truncation.
      if found.error != ReportReadError.Missing:
        return error(id, 0, "Invalid or unreadable work reports") # Malformed state is not ordinary absence.
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":2,\"message\":\"Work-report unavailable\",\"data\":" &
        quote(hash) & "}}"
  if methodName in ["serviceData", "serviceValue", "servicePreimage", "serviceRequest"]:
    let count = if methodName == "serviceData": 2 elif methodName == "serviceRequest": 4 else: 3
    if parameters < 0: return error(id, -32602, "Expected service query arguments") # Hash and service are mandatory.
    let first = parameters + 1
    if values[parameters].next != first + count: return error(id, -32602,
        "Expected scalar service query arguments") # No extra or nested arguments.
    if values[first].kind != stringValue or not validHash(values[first].text):
      return error(id, -32602, "Expected padded Base64 header hash") # Validate identities before lookup.
    var service = 0'u32
    if not serviceNumber(values[first + 1], service): return error(id, -32602, "Expected uint32 service ID")
    var key: seq[byte] = @[]
    if count >= 3:
      # Storage keys are bounded arbitrary blobs; preimage identities have exactly 32 bytes.
      if values[first + 2].kind != stringValue: return error(id, -32602, "Expected Base64 key or hash")
      if methodName in ["servicePreimage", "serviceRequest"]:
        if not validHash(values[first + 2].text): return error(id, -32602, "Expected padded Base64 preimage hash")
      if not decodeBlob(values[first + 2].text, MaxServiceKeyBytes, key):
        return error(id, -32602, "Invalid or oversized Base64 key") # Bound hashing and decoder scratch.
    var length = 0'u32
    if methodName == "serviceRequest":
      if not serviceNumber(values[first + 3], length):
        return error(id, -32602, "Expected uint32 preimage length") # Parse without narrowing or allocation based on length.
    let hash = values[first].text
    let selected = resolveBlock(info.chain, hash)
    if selected.error != GenesisError.None:
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id &
          ",\"error\":{\"code\":1,\"message\":\"Block unavailable\",\"data\":" & quote(hash) &
          "}}" # Unknown blocks cannot yield a false absence verdict.
    let view = selected.value
    if methodName == "serviceRequest":
      var identity = default(array[32, byte])
      for j in 0..<32: identity[j] = key[j] # Canonical hash width was validated above.
      let request = services.serviceRequest(view, ServiceIndex(service), ServicePreimageHash(
          identity), RequestLength(length))
      if request.error == ServiceReadError.Missing:
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id &
            ",\"result\":null}" # Absence differs from an outstanding empty history.
      if request.error == ServiceReadError.AmbiguousNamespace:
        return error(id, 0, "Request namespace ambiguous under pinned GP 0.8.0") # Do not interpret storage/preimage bytes as slots.
      if request.error != ServiceReadError.None:
        return error(id, 0, "Invalid or unreadable service request") # Malformed state never becomes null or [].
      let history = request.value
      var slots = ""
      case history.state
      of RequestState.Requested: discard # A requested but unprovided preimage has no timestamps.
      of RequestState.Available: slots = $uint32(history.since) # Supplied-at slot.
      of RequestState.Unavailable:
        slots = $uint32(history.availableFrom) & "," & $uint32(history.unavailableFrom) # Supplied then forgotten.
      of RequestState.Reavailable:
        slots = $uint32(history.originalFrom) & "," & $uint32(history.removedAt) & "," & $uint32(
            history.restoredAt) # Requested again.
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":[" & slots & "]}"
    # Reserve the envelope and exact quoted ID before converting the remaining budget to raw bytes.
    let budget = ByteLimit(min(MaxBlobReplyBytes, max(0, (allowance - id.len - 256) div 4 * 3)))
    var found = default(ServiceReadResult)
    if methodName == "serviceData":
      found = services.serviceData(view, ServiceIndex(service), budget) # Metadata uses C(255, service).
    elif methodName == "serviceValue":
      found = services.serviceValue(view, ServiceIndex(service), key, budget) # Empty raw keys remain valid.
    else:
      # Exact hash width was established before selecting the known block snapshot.
      var identity = default(array[32, byte])
      for j in 0..<32: identity[j] = key[j]
      found = services.servicePreimage(view, ServiceIndex(service), ServicePreimageHash(identity), budget)
    if found.error == ServiceReadError.Missing:
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id &
          ",\"result\":null}" # Absence differs from a present empty blob.
    if found.error == ServiceReadError.LimitExceeded: return error(id, 0,
        ReplyBudgetError) # Never truncate a stored value.
    if found.error != ServiceReadError.None: return error(id, 0,
        "Invalid or unreadable service state") # Do not publish malformed imported state.
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(
        found.value.bytes)) & "}"
  if methodName in ["parent", "stateRoot", "statistics", "listServices", "beefyRoot",
      "ragnarok_header"]:
    if parameters < 0: return error(id, -32602, "Expected one header hash") # Hash lookup always needs an argument.
    let argument = parameters + 1
    if values[parameters].next != argument + 1 or values[argument].kind != stringValue:
      return error(id, -32602, "Expected one header hash") # Exactly one scalar positional argument.
    let hash = values[argument].text
    if not validHash(hash): return error(id, -32602,
        "Expected padded Base64 hash") # Reject malformed identities before lookup.
    let selected = resolveBlock(info.chain, hash, methodName == "parent")
    if selected.error == GenesisError.None:
      let view = selected.value
      if methodName == "parent":
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & descriptor(view) &
            "}" # Only provider-backed parents succeed.
      if methodName == "ragnarok_header":
        # Retain the canonical sealed header; its bytes are exactly those hashed at genesis capture.
        let owner = view.header
        let metadata = headerInfo(owner)
        if metadata.error != HeaderError.None:
          return error(id, 0, "Invalid header owner") # Failed owners cannot supply lengths or bytes.
        let budget = min(MaxBlobReplyBytes, max(0, (allowance - id.len - 256) div 4 * 3))
        if metadata.value.consumed > budget:
          return error(id, 0, ReplyBudgetError) # Check complete size before allocation, copying or Base64 encoding.
        var bytes = newSeq[byte](metadata.value.consumed)
        if encodeOwnedHeader(owner, bytes).error != HeaderError.None:
          return error(id, 0, "Unreadable header") # Never publish partial encodings.
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(
            bytes)) & "}"
      if methodName == "listServices":
        # Retained scalar IDs are already sorted; never rescan or decode the map per request.
        var ids = "["
        let budget = max(0, allowance - id.len - 256)
        for index in 0..<view.serviceCount:
          let item = $uint32(view.serviceAt(ServiceListIndex(index)))
          if ids.len + item.len + 2 > budget:
            return error(id, 0, ReplyBudgetError) # Reserve comma/closing bracket; never return a partial list.
          if index > 0: ids.add(',') # The first member needs no separator.
          ids.add(item)
        ids.add(']')
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & ids & "}"
      if methodName == "beefyRoot":
        # The fixed commitment comes from the complete matching history, not a guessed empty root.
        let found = beefy.beefyRoot(view)
        if found.error != BeefyReadError.None:
          return error(id, 0, "Invalid or unavailable BEEFY history") # No root is exposed on failure.
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(
          array[32, byte](found.value))) & "}"
      if methodName == "statistics":
        # Use the same raw-value and aggregate reply ceilings as service blobs.
        let budget = ByteLimit(min(MaxBlobReplyBytes, max(0, (allowance - id.len - 256) div 4 * 3)))
        let found = statistics.statistics(view, budget)
        if found.error == StatisticsReadError.LimitExceeded:
          return error(id, 0, ReplyBudgetError) # A complete value must fit; no truncation.
        if found.error != StatisticsReadError.None:
          return error(id, 0, "Invalid or unavailable activity statistics") # Missing chapters are not empty statistics.
        return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(
            found.value.bytes)) & "}"
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & quote(base64.encode(array[32,
          byte](view.stateRoot))) & "}"
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"error\":{\"code\":1,\"message\":\"Block unavailable\",\"data\":" &
        quote(hash) & "}}" # No parent or unknown block data exists in this genesis-only view.
  if methodName in ["ragnarok_clientInfo", "parameters", "bestBlock"]:
    if parameters >= 0 and values[parameters].next != parameters + 1: return error(id, -32602, "Expected no parameters")
    if methodName == "bestBlock":
      if info.chain.bestBlock.error != GenesisError.None: return error(id, 0,
          "Genesis chain view unavailable") # No configured head exists.
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & descriptor(
          info.chain.bestBlock.value) & "}"
    if methodName == "parameters":
      if not info.parameters.ok: return error(id, 0, "Chain parameters unavailable; configure --chain")
      return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & parameterObject(
          info.parameters.value, info.chain.bestBlock) & "}"
    return "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"result\":" & clientInfo(info) & "}"
  error(id, -32601, "Method not available") # Chain queries/subscriptions are unavailable until backed by actual state.

# Determine the exact encoded ID length for output reservation; invalid envelopes may reserve excess.
proc requestId(values: seq[Value], start: int): string =
  result = "null"
  if values[start].kind != objectValue: return # Invalid nonobjects have a small null-ID error.
  var i = start + 1
  # Mirror only ID rendering; dispatchImpl remains responsible for all envelope validity checks.
  while i < values[start].next:
    let name = values[i].text
    inc i
    if name == "id":
      if values[i].kind == stringValue: result = quote(values[i].text) # Account for escaping expansion.
      elif values[i].kind == numberValue: result = values[i].text # Preserve arbitrary numeric lexemes.
      else: result = "null" # Null and invalid ID types cannot require a longer reservation.
    i = values[i].next

# Bound every method's final response, including fixed methods appearing after large blob results.
proc dispatch(values: seq[Value], start: int, info: ClientInfo, allowance = MaxReplyBytes): string =
  result = dispatchImpl(values, start, info, allowance)
  if result.len > allowance:
    result = error(requestId(values, start), 0, ReplyBudgetError) # Preserve the request ID in a bounded fallback.

# Parse and execute one whole message atomically; empty output means a notification-only message.
proc respond*(text: string, info: ClientInfo): string =
  if text.len == 0 or text.len > MaxMessage or not validUtf8(text): return error("null", -32700, "Parse error")
  var values: seq[Value] = @[]
  if not parseValues(text, values): return error("null", -32700, "Parse error")
  if values[0].kind != arrayValue: return dispatch(values, 0, info)
  var starts: seq[int] = @[]
  var reserves: seq[int] = @[]
  var available = MaxReplyBytes - 2
  var i = 1
  # Reserve each reply's exact ID and fallback envelope before allowing any blob to consume capacity.
  while i < values.len:
    if starts.len == 16: return error("null", -32600, "Invalid batch size") # Bound metadata before insertion.
    starts.add(i)
    let reserved = error(requestId(values, i), 0, ReplyBudgetError).len + 128
    reserves.add(reserved)
    available -= reserved + 1 # One conservative comma reservation per member.
    i = values[i].next
  if starts.len == 0: return error("null", -32600, "Invalid batch size") # Empty arrays are invalid requests.
  if available < 0: return error("null", 0, ReplyBudgetError) # Defensive guard if input/ID policies change.
  result = ""
  # Each reply can spend only free space plus its own reservation; later request IDs stay representable.
  for index, start in starts:
    let allowance = available + reserves[index]
    let response = dispatch(values, start, info, allowance)
    available = allowance - response.len
    if response.len > 0:
      if result.len > 0: result.add(',') # Notifications contribute neither a reply nor a separator.
      result.add(response)
  if result.len > 0: result = "[" & result & "]" # Notification-only batches produce no frame.
