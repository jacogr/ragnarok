# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent assurances adapter, including deliberate overlap and lifetime probes.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/assurances as codec_assurances

# Bound and validate test hex independently of the production wire decoder.
proc unhex(text: string): seq[byte] {.raises.} =
  # Dash preserves an empty line-protocol token.
  if text == "-": return @[]
  assert text.len mod 2 == 0 and text.len <= 300000
  result = newSeq[byte](text.len div 2)
  # Validate both nibbles before constructing each trusted source byte.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair:
      # Uppercase and nonhex text are harness errors.
      assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Print every actual output byte, using dash for an empty logical sequence.
proc hexText(data: openArray[byte]): string =
  # An explicit empty token keeps subsequent numeric fields distinct.
  if data.len == 0: return "-"
  result = ""
  # Hex conversion is confined to the trusted adapter boundary.
  for value in data: result.add(toHex(int(value), 2).toLowerAscii())

# Parse a bounded host allocation size; production resource limits remain separate.
proc capacity(text: string, maximum: int): int {.raises.} =
  result = parseInt(text)
  assert result >= 0 and result <= maximum

# Initialize every named field, including unused bitset bytes, for atomicity tests.
proc sentinel(): Assurance =
  result = default(Assurance)
  # Make all 32 anchor bytes observable after a failed decode.
  for i in 0..<32: result.anchor.bytes[i] = 77
  # Unused storage must survive failure too.
  for i in 0..<43: result.bits.bytes[i] = 77
  result.validator = ValidatorIndex(77)
  # Signatures have their own independent identity domain.
  for i in 0..<64: result.signature.bytes[i] = 77

# Construct logical source fields without calling the new wire decoder.
proc records(data: openArray[byte]): seq[Assurance] =
  assert data.len mod 141 == 0
  result = newSeq[Assurance](data.len div 141)
  # Logical records retain full native bitset storage regardless of configured wire width.
  for i in 0..<result.len:
    let start = i*141
    # Construct the declared anchor directly.
    for j in 0..<32: result[i].anchor.bytes[j] = data[start+j]
    # Include octets outside the selected profile to test encoder rejection.
    for j in 0..<43: result[i].bits.bytes[j] = data[start+32+j]
    result[i].validator = ValidatorIndex(uint16(data[start+75]) or (uint16(data[start+76]) shl 8))
    # Preserve all independent signature bytes.
    for j in 0..<64: result[i].signature.bytes[j] = data[start+77+j]

# Render named fields independently of encoder ordering and native struct padding.
proc logical(values: openArray[Assurance]): seq[byte] =
  result = @[]
  # Every record contributes the same complete fixed logical layout.
  for value in values:
    # Copy each anchor identity byte without interpreting native object padding.
    for octet in value.anchor.bytes: result.add(octet)
    # Include every bitset storage byte, including unused profile octets.
    for octet in value.bits.bytes: result.add(octet)
    result.add(byte(uint16(value.validator) and 255))
    result.add(byte(uint16(value.validator) shr 8))
    # Copy every opaque signature byte independently of struct layout.
    for octet in value.signature.bytes: result.add(octet)

# Verify full sentinel spans, including bytes beyond the encoder's returned extent.
proc unchanged(data: openArray[byte]) =
  # Partial commits are failures even if returned metadata hides them.
  for value in data: assert value == 77

# Parse the complete unsigned fixture domain without narrowing through a signed host integer.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

# Execute frozen equivalent operations with independent construction and ownership assertions.
proc request(p: seq[string]) {.raises.} =
  let config = AssuranceConfig(cores: CoreCount(unsigned(p[1])),
                               validators: ValidatorCount(unsigned(p[2])))
  case p[0]
  of "E":
    # Typed source construction is independent of the new wire decode operation.
    let values = records(unhex(p[4]))
    let cap = capacity(p[3], 150000)
    var output = newSeq[byte](cap+3)
    # Fill active and trailing destination bytes before calling production code.
    for value in output.mitems: value = 77
    let encoded = encodeAssurances(values, config, output.toOpenArray(0, cap-1))
    if encoded.error != AssuranceError.None:
      # A failed final record must preserve every prior output byte.
      unchanged(output)
      echo ($encoded.error).toLowerAscii()
    else:
      # Success cannot write beyond its returned extent.
      unchanged(output.toOpenArray(encoded.written, output.high))
      echo hexText(output.toOpenArray(0, encoded.written-1))
  of "D":
    # Decode into bounded typed capacity, with two extra records that must survive unchanged.
    var data = unhex(p[4])
    var saved = newSeq[byte](data.len)
    # Keep an explicit independent expectation before overwriting the caller input.
    for i in 0..<data.len: saved[i] = data[i]
    let cap = capacity(p[3], 1024)
    var output = newSeq[Assurance](cap+2)
    # Explicit initialization makes late failure observable across every named field.
    for value in output.mitems: value = sentinel()
    let before = logical(output)
    let decoded = decodeAssurances(data, config, output.toOpenArray(0, cap-1))
    if decoded.error != AssuranceError.None:
      # Failed decoders must preserve the entire typed destination.
      assert logical(output) == before
      echo ($decoded.error).toLowerAscii()
    else:
      # Overwrite source bytes before inspecting retained decoded fields.
      for value in data.mitems: value = 0
      assert logical(output.toOpenArray(decoded.count, output.high)) == before.toOpenArray(
          decoded.count*141, before.high)
      let bytes = logical(output.toOpenArray(0, decoded.count-1))
      var encoded = newSeq[byte](decoded.consumed)
      let check = encodeAssurances(output.toOpenArray(0, decoded.count-1), config, encoded)
      assert check.error == AssuranceError.None and check.written == decoded.consumed
      assert encoded == saved.toOpenArray(0, decoded.consumed-1)
      echo $decoded.count & " " & hexText(bytes) & " " & $decoded.consumed
  of "I":
    # Inspect directly without caller record allocation; compare independent count/extent expectations.
    let scanned = inspectAssurances(unhex(p[3]), config)
    if scanned.error == AssuranceError.None:
      # Successful inspection exposes only validated prefix metadata.
      echo $scanned.count & " " & $scanned.consumed
    else:
      # Failed inspection must preserve the precise structural/semantic reason.
      echo ($scanned.error).toLowerAscii()
  else:
    # Unsafe byte views are limited to deliberate trusted overlap tests.
    let data = unhex(p[3])
    # Fixed aligned storage has room for the maximum profile and an extra count-prefix record.
    var values = default(array[1026, Assurance])
    var count = 0
    if p[0] == "XE":
      # Construct typed source values independently before manufacturing the aliased destination.
      let source = records(data)
      count = source.len
      assert count < values.len
      # Copy the complete typed records; unused storage is still part of the mutation sentinel.
      for i in 0..<count: values[i] = source[i]
    else:
      # Decode uses the same correctly aligned allocation as its trusted byte-view source.
      assert p[0] == "XD"
    let size = sizeof(values)
    let raw = cast[ptr array[sizeof(values), byte]](addr values[0])
    assert data.len <= size
    if p[0] == "XD":
      # Copy only actual wire bytes into a view covering exactly the allocated typed storage.
      copyMem(cast[pointer](raw), unsafeAddr data[0], data.len)
    let saved = @(raw[].toOpenArray(0, size-1))
    if p[0] == "XE":
      # The dereferenced fixed array provides a writable view through public language facilities.
      let encoded = encodeAssurances(values.toOpenArray(0, count-1), config,
          raw[].toOpenArray(0, size-1))
      assert encoded.error == AssuranceError.AliasedBuffers
      echo ($encoded.error).toLowerAscii()
    else:
      # Full-input overlap must be rejected before any typed record commit.
      let decoded = decodeAssurances(raw[].toOpenArray(0, data.high), config, values)
      assert decoded.error == AssuranceError.AliasedBuffers
      echo ($decoded.error).toLowerAscii()
    assert @(raw[].toOpenArray(0, size-1)) == saved

# A single native process handles all frozen requests with no Python runtime involvement.
proc main() {.raises.} =
  assert paramCount() == 1
  # Batch-file allocation belongs only to this trusted fixture utility, never production decoding.
  for line in readFile(paramStr(1)).splitLines():
    if line.len == 0:
      # A trailing newline is not a codec operation.
      continue
    let parts = line.splitWhitespace()
    assert parts.len in [4, 5]
    request(parts)

# File/fixture failures must fail this adapter without fallback or silently skipping requests.
try:
  main()
except:
  # A malformed trusted batch is a test failure rather than a production decode result.
  quit 2
