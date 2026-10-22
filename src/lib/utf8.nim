# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict Unicode scalar validation shared by byte-oriented interfaces.

proc validUtf8*(text: string): bool =
  ## Validate Unicode scalar encodings, excluding overlong sequences, surrogates and out-of-range values.
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

