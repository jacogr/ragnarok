## Independent fixed source fields and retained logical observations for T chapter 16.
import std/[os, strutils]
import ../../src/[state_outputs, state_trie, bounded]

## Preserve empty input without adding an encoded zero to hostile wire cases.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty transport token differs from a valid zero count byte.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1])) # Preserve exact fixed octets.

## Observe complete output bytes and opaque commitments without integer/hash reinterpretation.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty fields remain representable in the trusted transport.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii()) # Leading zeroes and count framing remain visible.

## Execute one source or raw-wire request against the public typed owner API.
proc request(parts: seq[string]) =
  let config = OutputLogConfig(items: ElementLimit(parseBiggestUInt(parts[1])), maxBytes: ByteLimit(
      parseBiggestUInt(parts[2])))
  case parts[0]
  of "V", "R":
    var values: seq[AccumulationOutput]
    if parts[3] != "-":
      for i in 3..<parts.len:
        let fields = parts[i].split(':')
        let bytes = unhex(fields[1])
        doAssert bytes.len == 32
        var commitment: array[32, byte]
        for j in 0..<32: commitment[j] = bytes[j] # Literal source commitments are independent of native decoding.
        values.add(AccumulationOutput(service: ServiceIndex(parseBiggestUInt(fields[0])),
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
        doAssert root.error == StateTrieError.None
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
  else: doAssert false # Trusted operation cannot silently select another protocol component.

# Each request independently releases temporary sources, encoded entries and retained owners.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines are ignored.
