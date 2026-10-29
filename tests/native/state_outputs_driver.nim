# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent fixed source fields and retained logical observations for T chapter 16.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/[assertions, cmdline, syncio, strutils, parseutils]
import ../../src/codec/state/[outputs as state_outputs, trie as state_trie]
import ../../src/codec/bounded

## Preserve empty input without adding an encoded zero to hostile wire cases.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty transport token differs from a valid zero count byte.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Each trusted transport byte has exactly two lowercase hexadecimal digits.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Reject malformed fixture tokens before converting their literal octets.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Observe complete output bytes and opaque commitments without integer/hash reinterpretation.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty fields remain representable in the trusted transport.
  result = ""
  # Preserve all supplied octets, including leading zeroes.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii()) # Leading zeroes and count framing remain visible.

## Parse a complete trusted uint64 token through the supported nonthrowing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Execute one source or raw-wire request against the public typed owner API.
proc request(parts: seq[string]) =
  let config = OutputLogConfig(items: ElementLimit(unsigned(parts[1])), maxBytes: ByteLimit(
      unsigned(parts[2])))
  case parts[0]
  of "V", "R":
    var values: seq[AccumulationOutput] = @[]
    if parts[3] != "-":
      for i in 3..<parts.len:
        let fields = parts[i].split(':')
        let bytes = unhex(fields[1])
        assert bytes.len == 32
        var commitment = default(array[32, byte])
        for j in 0..<32: commitment[j] = bytes[j] # Literal source commitments are independent of native decoding.
        values.add(AccumulationOutput(service: ServiceIndex(unsigned(fields[0])),
            commitment: OutputCommitment(commitment)))
    let encoded = outputLogEntry(values, config)
    if encoded.error != OutputLogError.None:
      echo ($encoded.error).toLowerAscii() # No fabricated key or bytes after preflight failure.
    else:
      for i in 0..<values.len: values[i] = default(
          AccumulationOutput) # Fresh output must survive source destruction.
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # C(16)-only root, not a complete JAM state.
        assert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    var bytes = unhex(parts[3])
    let parsed = decodeOutputLog(bytes, config)
    if parsed.error != OutputLogError.None:
      echo ($parsed.error).toLowerAscii() # No partial earlier pairs or cursor on late truncation.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # Retained fixed values cannot depend on caller wire.
      let owner = parsed.value.snapshot
      let count = outputLogCount(owner).value
      var output = $parsed.value.consumed & " " & $count
      for i in 0..<count:
        let value = outputLogAt(owner, OutputLogIndex(i)).value
        output.add(" " & $uint32(value.service) & ":" & hex(array[32, byte](
            value.commitment))) # Observe logical fields without production re-encoding.
      echo output
  else: assert false # Trusted operation cannot silently select another protocol component.

# Each request independently releases temporary sources, encoded entries and retained owners.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines are ignored.
