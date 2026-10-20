# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structured JSON output for the pinned Nimony runtime. Values own serialized bytes;
## objects and arrays handle separators, strings handle escaping, integers retain their full width.
## Callers validate UTF-8 and enforce their own byte budgets before adding untrusted payloads.

import std/strutils

type
  JsonValue* = object ## Complete JSON value; the default value represents null.
    text: string
  JsonObject* = object ## Ordered fields accumulated without retaining caller-owned data.
    fields: string
  JsonArray* = object ## Ordered elements accumulated without retaining caller-owned data.
    elements: string

proc `$`*(value: JsonValue): string =
  ## Serialize a complete value, including the default null value.
  if value.text.len == 0: "null" else: value.text

proc jsonNull*(): JsonValue =
  ## Construct the JSON null literal.
  JsonValue(text: "null")

proc trustedJson*(text: string): JsonValue =
  ## Embed exactly one already validated JSON value without parsing or numeric conversion.
  ## This is an explicit trust boundary: never pass arbitrary text or object/array fragments.
  JsonValue(text: text)

proc json*(value: string): JsonValue =
  ## Quote UTF-8 text, escaping ASCII controls, backslashes and double quotes.
  var text = "\""
  for c in value:
    # Preserve ordinary UTF-8 bytes; JSON delimiters and ASCII controls need escaping.
    if c == '"' or c == '\\':
      text.add('\\')
      text.add(c)
    elif ord(c) < 32:
      text.add("\\u00" & toHex(ord(c), 2))
    else:
      text.add(c)
  text.add('"')
  JsonValue(text: text)

proc json*(value: int8): JsonValue =
  ## Encode int8 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: int16): JsonValue =
  ## Encode int16 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: int32): JsonValue =
  ## Encode int32 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: int64): JsonValue =
  ## Encode int64 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: uint8): JsonValue =
  ## Encode uint8 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: uint16): JsonValue =
  ## Encode uint16 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: uint32): JsonValue =
  ## Encode uint32 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: uint64): JsonValue =
  ## Encode uint64 directly as decimal without signed narrowing or floating point.
  JsonValue(text: $value)

proc json*(value: bool): JsonValue =
  ## Encode a JSON boolean literal.
  JsonValue(text: (if value: "true" else: "false"))

proc len*(value: JsonArray): int =
  ## Exact encoded byte count, including the eventual square brackets.
  value.elements.len + 2

proc add*(output: var JsonObject, key: string, value: JsonValue) =
  ## Append one named field in insertion order; callers choose unique keys.
  if output.fields.len > 0:
    output.fields.add(',') # Only subsequent fields need a separator.
  output.fields.add($json(key))
  output.fields.add(':')
  output.fields.add($value)

proc add*(output: var JsonArray, value: JsonValue) =
  ## Append one complete element, handling its separator centrally.
  if output.elements.len > 0:
    output.elements.add(',') # Empty arrays have no leading separator.
  output.elements.add($value)

proc json*(value: JsonObject): JsonValue =
  ## Finish a field builder as one complete JSON object.
  JsonValue(text: "{" & value.fields & "}")

proc json*(value: JsonArray): JsonValue =
  ## Finish an element builder as one complete JSON array.
  JsonValue(text: "[" & value.elements & "]")

proc jsonObject*(fields: openArray[(string, JsonValue)]): JsonValue =
  ## Build an object from named values, handling nesting and escaping through JsonValue.
  var output = JsonObject(fields: "")
  for field in fields:
    output.add(field[0], field[1]) # Preserve the supplied field order.
  json(output)
