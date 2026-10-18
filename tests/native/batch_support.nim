# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted batch transport helpers; reject numeric overflow before Nimony's intentional wrapping.
import std/[assertions, parseutils, strutils]

# Parse an entire unsigned token without signed narrowing, exceptions or wraparound.
proc parseUnsigned*(text: string, value: var uint64): bool =
  if text.len == 0: return false # Empty transport text is not a decimal value.
  var number: uint64 = 0
  # Validate before multiply/add so out-of-domain text never reaches the production codec.
  for c in text:
    if c < '0' or c > '9': return false # Signs and nondecimal characters are invalid.
    let digit = uint64(ord(c)-ord('0'))
    if number > (high(uint64)-digit) div 10: return false # Reject the first overflowing digit.
    number = number*10+digit
  value = number
  true

# Trusted valid uint64 fixture fields use the same checked parser as hostile primitive text.
proc unsigned*(text: string): uint64 =
  result = 0
  assert parseUnsigned(text, result)

# Parse signed width/capacity fields, including both host-int extremes, without negating low(int).
proc parseSigned*(text: string, value: var int): bool =
  if text.len == 0: return false # A sign still needs at least one digit.
  let negative = text[0] == '-'
  var magnitude: uint64 = 0
  if not parseUnsigned(if negative: text[1..^1] else: text, magnitude): return false
  let ceiling = uint64(high(int)) + uint64(ord(negative))
  if magnitude > ceiling: return false # Do not narrow an unrepresentable host integer.
  if negative:
    # This formulation represents low(int) without an overflowing positive intermediate.
    value = if magnitude == 0: 0 else: -int(magnitude-1)-1
  else:
    value = int(magnitude) # The positive magnitude is already proven representable.
  true

# Other batch protocols contain trusted valid host integers; codec width failures remain codec results.
proc integer*(text: string): int =
  result = 0
  assert parseSigned(text, result)

# Parse exactly one lowercase byte pair, with no throwing string conversion API.
proc octet*(text: string): byte =
  assert text.len == 2
  # Explicit spelling checks prevent a permissive hexadecimal parser from accepting other syntax.
  for c in text: assert c in {'0'..'9', 'a'..'f'}
  result = 0
  assert parseHex(text, result) == 2
