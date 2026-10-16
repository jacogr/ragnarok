## Independent tagged source histories and fixed-copy observations for service request entries.
import std/[os, strutils]
import ../../src/[state_requests, state_trie, bounded]

## Preserve malformed empty input without inserting a valid empty-history count.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty trusted token differs from protocol requested-mode zero.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[
      2*i..2*i+1])) # Preserve exact count/timestamp/hash bytes.

## Display complete fixed keys/raw history bytes without manufacturing expected framing.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Trusted transport always needs one token per logical field.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii()) # Leading zeroes matter in fixed E4 fields and hashes.

## Construct one exact tagged alternative directly from decimal timeslots, independently of wire decoding.
proc history(parts: seq[string]): RequestHistory =
  let count = parseInt(parts[7])
  doAssert parts.len == 8+count
  case count
  of 0: RequestHistory(state: RequestState.Requested) # No nonexistent source timestamp field.
  of 1: RequestHistory(state: RequestState.Available, since: RequestSlot(parseBiggestUInt(parts[
      8]))) # Single supplied-at value.
  of 2: RequestHistory(state: RequestState.Unavailable, availableFrom: RequestSlot(parseBiggestUInt(
      parts[8])),
    unavailableFrom: RequestSlot(parseBiggestUInt(parts[
        9]))) # Source order is preserved without chronology repair.
  of 3: RequestHistory(state: RequestState.Reavailable, originalFrom: RequestSlot(parseBiggestUInt(
      parts[8])),
    removedAt: RequestSlot(parseBiggestUInt(parts[9])), restoredAt: RequestSlot(parseBiggestUInt(
        parts[10]))) # Restoration has three active fixed values.
  else: raise newException(ValueError, "invalid trusted source shape") # No unsafe four-slot variant is fabricated.

## Observe only actual active fields, never production re-encoded answers or unused default slots.
proc observed(value: RequestHistoryRead): string =
  result = $value.consumed & " " & $ord(value.history.state)
  case value.history.state
  of RequestState.Requested: discard # Requested mode publishes no timestamp values.
  of RequestState.Available: result.add(" " & $uint32(value.history.since)) # One active availability time.
  of RequestState.Unavailable: result.add(" " & $uint32(value.history.availableFrom) & " " &
      $uint32(value.history.unavailableFrom)) # Preserve both original positions.
  of RequestState.Reavailable: result.add(" " & $uint32(value.history.originalFrom) & " " & $uint32(
      value.history.removedAt) & " " & $uint32(value.history.restoredAt)) # No chronology inference.

## Execute one raw decode or independent typed-source entry request.
proc request(parts: seq[string]) =
  if parts[0] == "D":
    let config = RequestHistoryConfig(items: ElementLimit(parseBiggestUInt(parts[1])),
        maxBytes: ByteLimit(parseBiggestUInt(parts[2])))
    var input = unhex(parts[3])
    let parsed = decodeRequestHistory(input, config)
    if parsed.error != RequestError.None:
      echo ($parsed.error).toLowerAscii() # No default requested history or partial consumed extent on failure.
    else:
      for i in 0..<input.len: input[i] = 0 # Returned fixed tagged fields must survive input destruction.
      echo observed(parsed.value)
  else:
    doAssert parts[0] == "V" or parts[0] == "R" # Trusted operations select entry bytes or one partial root.
    let config = RequestEntryConfig(keyBytes: ByteLimit(parseBiggestUInt(parts[1])),
        history: RequestHistoryConfig(
      items: ElementLimit(parseBiggestUInt(parts[2])), maxBytes: ByteLimit(parseBiggestUInt(parts[3]))))
    let service = ServiceIndex(parseBiggestUInt(parts[4]))
    var bytes = unhex(parts[5])
    doAssert bytes.len == 32
    var hash: array[32, byte]
    for i in 0..<32: hash[i] = bytes[i] # Literal fixed hash source, separate from stored key construction.
    var value = history(parts)
    let encoded = serviceRequestEntry(service, ServicePreimageHash(hash), RequestLength(
        parseBiggestUInt(parts[6])), value, config)
    if encoded.error != RequestError.None:
      echo ($encoded.error).toLowerAscii() # No fabricated default key/value after history/key policy failure.
    else:
      value = default(RequestHistory)
      for i in 0..<bytes.len: bytes[i] = 0 # Fresh output cannot depend on the source hash buffer or tagged value.
      hash = default(array[32, byte])
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # One request entry, not whole-service or JAM state.
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))

# Each request releases caller buffers independently; decoded histories require no retained heap owner.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines contain no operation.
