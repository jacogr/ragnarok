# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted batch adapter exposes complete roots/counts or failure-only reasons.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/[state_trie, state_layout, bounded]

## Read exact trusted hex tokens; production state values remain raw bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty values need one whitespace token.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Preserve each source octet and its original order.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted hexadecimal tokens must contain exactly two lowercase digits per fixture byte.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Observe root bytes without losing leading zeroes.
proc hex(root: StateRoot): string =
  result = ""
  # Roots are fixed copied values, independent of entry backing storage.
  for b in array[32, byte](root): result.add(toHex(int(b), 2).toLowerAscii())

# Parse the complete unsigned fixture domain without signed narrowing or implicit overflow behavior.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Consume one complete trusted request and verify the implementation leaves caller inputs unchanged.
proc request(parts: seq[string]) {.raises.} =
  let limits = StateTrieLimits(items: ElementLimit(unsigned(parts[0])),
    perValue: ByteLimit(unsigned(parts[1])), totalValueBytes: ByteLimit(unsigned(parts[2])),
    nodes: TrieNodeLimit(unsigned(parts[3])))
  let count = parseInt(parts[4])
  assert parts.len == 5+count*2
  var entries = newSeq[StateEntry](count)
  # Exact fixed keys cannot be silently truncated or normalized by the adapter.
  for i in 0..<count:
    let bytes = unhex(parts[5+i*2])
    assert bytes.len == 31
    var key = default(array[31, byte])
    # Copy the full current key domain from independently authored sources.
    for j in 0..<31: key[j] = bytes[j]
    entries[i] = StateEntry(key: StateKey(key), value: unhex(parts[6+i*2]))
  let parsed = stateTrieRoot(entries, limits)
  # Both successful and rejected calls must leave source order and payload bytes intact.
  for i in 0..<count:
    assert entries[i].value == unhex(parts[6+i*2])
    assert @(array[31, byte](entries[i].key)) == unhex(parts[5+i*2])
  if parsed.error != StateTrieError.None:
    echo ($parsed.error).toLowerAscii() # No root or progress exists on this variant.
  else:
    # Destroy backing payloads before observing the returned fixed root.
    for i in 0..<count:
      for j in 0..<entries[i].value.len: entries[i].value[
          j] = 0 # No retained payload aliases can affect the root.
    echo hex(parsed.value.root) & " " & $parsed.value.entries & " " & $parsed.value.nodes

# Keep trusted argument/file parsing outside the root calculator's typed protocol-failure contract.
proc main() {.raises.} =
  # Requests are independent and release source storage after each complete observation.
  for line in lines(paramStr(1)):
    if line.len > 0: request(line.splitWhitespace()) # Empty batch lines have no operation.
try:
  main()
except:
  # Trusted transport errors fail independently from ordinary protocol rejection.
  quit(2)
