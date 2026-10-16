## Trusted batch adapter exposes complete roots/counts or failure-only reasons.
import std/[os, strutils]
import ../../src/[state_trie, state_layout, bounded]

## Read exact trusted hex tokens; production state values remain raw bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty values need one whitespace token.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Preserve each source octet and its original order.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Observe root bytes without losing leading zeroes.
proc hex(root: StateRoot): string =
  # Roots are fixed copied values, independent of entry backing storage.
  for b in array[32, byte](root): result.add(toHex(b, 2).toLowerAscii())

## Consume one complete trusted request and verify the implementation leaves caller inputs unchanged.
proc request(parts: seq[string]) =
  let limits = StateTrieLimits(items: ElementLimit(parseBiggestUInt(parts[0])),
    perValue: ByteLimit(parseBiggestUInt(parts[1])), totalValueBytes: ByteLimit(parseBiggestUInt(
        parts[2])),
    nodes: TrieNodeLimit(parseBiggestUInt(parts[3])))
  let count = parseInt(parts[4])
  doAssert parts.len == 5+count*2
  var entries = newSeq[StateEntry](count)
  # Exact fixed keys cannot be silently truncated or normalized by the adapter.
  for i in 0..<count:
    let bytes = unhex(parts[5+i*2])
    doAssert bytes.len == 31
    var key: array[31, byte]
    # Copy the full current key domain from independently authored sources.
    for j in 0..<31: key[j] = bytes[j]
    entries[i] = StateEntry(key: StateKey(key), value: unhex(parts[6+i*2]))
  let parsed = stateTrieRoot(entries, limits)
  # Both successful and rejected calls must leave source order and payload bytes intact.
  for i in 0..<count:
    doAssert entries[i].value == unhex(parts[6+i*2])
    doAssert @(array[31, byte](entries[i].key)) == unhex(parts[5+i*2])
  if parsed.error != StateTrieError.None:
    echo ($parsed.error).toLowerAscii() # No root or progress exists on this variant.
  else:
    # Destroy backing payloads before observing the returned fixed root.
    for i in 0..<count:
      for j in 0..<entries[i].value.len: entries[i].value[
          j] = 0 # No retained payload aliases can affect the root.
    echo hex(parsed.value.root) & " " & $parsed.value.entries & " " & $parsed.value.nodes

# Requests are independent and release all mutable source storage at the end of each call.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Ignore empty trusted transport lines.
