# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded strict JSON tokens shared by independent method registries. Callers bound input bytes
## and validate raw UTF-8 before parsing; decoded strings are checked again after unescaping.

import std/[parsejson, streams]
import ../utf8

# Flat tokens retain exact numeric lexemes and decoded text; next skips a complete subtree.
type
  JsonKind* = enum ## Parsed JSON alternatives; literals retain their exact spelling.
    objectValue, arrayValue, stringValue, numberValue, literalValue
  JsonToken* = object ## Owned token data with an exclusive subtree end index.
    kind*: JsonKind
    text*: string
    next*: int
  JsonContainer = object ## Private bounded parser stack frame tracks object key positions.
    index, children: int

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
proc parseValues*(text: string, values: var seq[JsonToken], maxValues = 2048, maxDepth = 16): bool =
  if not strictLexemes(text): return false
  var parser = default(JsonParser)
  parser.open(newStringStream(text), "RPC request")
  defer: parser.close()
  var containers: seq[JsonContainer] = @[]
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
      var token = JsonToken(kind: literalValue, text: "", next: values.len + 1)
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
        containers.add(JsonContainer(index: values.len - 1, children: 0)) # Bounded open-container stack.

