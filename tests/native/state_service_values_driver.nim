## Trusted source fields and immutable raw-value observations for service storage/preimage entries.
import std/[os, strutils]
import ../../src/[state_service_values, state_trie, bounded]

## Preserve empty logical keys/values without adding framing bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Raw empty bytes differ from the one-byte value zero.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[
      2*i..2*i+1])) # Preserve exact binary keys and values.

## Display every observed byte without implicit natural counts or hash reinterpretation.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty raw payloads still occupy one trusted observation token.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii()) # Leading zeroes matter for namespaces and raw values.

## Execute independent source derivation or opaque existing-key capture using public typed APIs.
proc request(parts: seq[string]) =
  if parts[0] == "C":
    let limit = ByteLimit(parseBiggestUInt(parts[1]))
    let service = ServiceIndex(parseBiggestUInt(parts[2]))
    let keyBytes = unhex(parts[3])
    doAssert keyBytes.len == 31
    var key: array[31, byte]
    for i in 0..<31: key[i] = keyBytes[i] # Full original state key is retained without an original unhashed storage key.
    var value = unhex(parts[4])
    let captured = captureServiceValue(service, StateKey(key), value, limit)
    if captured.error != ServiceValueError.None:
      echo ($captured.error).toLowerAscii() # Failure exposes no key/owner/count.
    else:
      for i in 0..<value.len: value[i] = 0 # Retained bytes must survive original input mutation.
      key = default(array[31, byte])
      let owner = captured.value
      let info = serviceValueInfo(owner).value
      var output = newSeq[byte](info.length+3)
      for i in 0..<output.len: output[i] = 77 # Copy must leave destination suffix untouched.
      let copied = copyServiceValue(owner, output)
      doAssert copied.error == ServiceValueError.None and copied.value == info.length
      for i in info.length..<output.len: doAssert output[i] == 77 # No writes beyond the complete raw value.
      let encoded = serviceValueEntry(owner, limit)
      doAssert encoded.error == ServiceValueError.None and array[31, byte](encoded.value.key) ==
          array[31, byte](info.key)
      doAssert encoded.value.value.len == info.length
      for i in 0..<info.length: doAssert encoded.value.value[i] == output[
          i] # Re-emission remains associated with the captured key.
      echo hex(array[31, byte](info.key)) & " " & $uint32(info.service) & " " & $info.length & " " &
          hex(output.toOpenArray(0, info.length-1))
  else:
    doAssert parts[0] == "V" or parts[0] == "R" # Trusted operations select source bytes or one partial trie root.
    let limits = ServiceEntryLimits(keyBytes: ByteLimit(parseBiggestUInt(parts[2])),
        valueBytes: ByteLimit(parseBiggestUInt(parts[3])))
    let service = ServiceIndex(parseBiggestUInt(parts[4]))
    var identity = unhex(parts[5])
    var value = unhex(parts[6])
    var encoded: ServiceValueResult[StateEntry]
    if parts[1] == "S":
      encoded = serviceStorageEntry(service, identity, value,
          limits) # Raw storage keys remain unprefixed in trusted source transport.
    else:
      doAssert parts[1] == "P" and identity.len == 32
      var hash: array[32, byte]
      for i in 0..<32: hash[i] = identity[i] # Fixed preimage lookup identity has its own nominal domain.
      encoded = servicePreimageEntry(service, ServicePreimageHash(hash), value, limits)
    if encoded.error != ServiceValueError.None:
      echo ($encoded.error).toLowerAscii() # No fabricated key/value after policy/backend failure.
    else:
      for i in 0..<identity.len: identity[i] = 0 # Output key/value cannot alias either caller source.
      for i in 0..<value.len: value[i] = 0
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # This commits one mapping, not the whole service state.
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))

# Every request independently releases its temporary inputs and opaque retained owner.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines contain no request.
