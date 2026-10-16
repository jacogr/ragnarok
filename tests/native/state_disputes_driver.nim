## Trusted independent source/observation adapter for canonical chapter-5 sets.
import std/[os, strutils]
import ../../src/codec/[state_disputes, state_trie, bounded]

## Preserve empty set/input tokens without inventing a wire byte.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty sets and malformed empty wire remain expressible.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Exact octets, not host integer identities, determine canonical ordering.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Observe every fixed identity byte without losing leading zeroes.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty set position in whitespace transport.
  # Each identity is observed independently of the production encoder.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

## Build fixed source identities directly from trusted field schemas, not decoder output.
proc fixed(bytes: seq[byte], offset: int): array[32, byte] =
  # Trusted source row lengths are exact multiples of the identity width.
  for i in 0..<32: result[i] = bytes[offset+i]

## Read independent per-set, whole-component item and byte resource ceilings.
proc config(parts: seq[string]): DisputeStateConfig =
  DisputeStateConfig(perSet: ElementLimit(parseBiggestUInt(parts[1])), totalItems: ElementLimit(
      parseBiggestUInt(parts[2])),
    maxBytes: ByteLimit(parseBiggestUInt(parts[3])))

## Construct each nominal report/key set independently, allowing hostile source order and duplicates.
proc source(parts: seq[string]): DisputeState =
  doAssert parts.len == 8
  # Keep report classes in their exact good/bad/wonky positions.
  for kind in JudgmentSet:
    let bytes = unhex(parts[4+ord(kind)])
    doAssert bytes.len mod 32 == 0
    result.reports[kind] = newSeq[DisputeHash](bytes.len div 32)
    for i in 0..<result.reports[kind].len: result.reports[kind][i] = DisputeHash(fixed(bytes,
        i*32)) # Nominal copied sources.
  let bytes = unhex(parts[7])
  doAssert bytes.len mod 32 == 0
  result.offenders = newSeq[OffenderKey](bytes.len div 32)
  # Offender source identities are keys, not report hashes of equal width.
  for i in 0..<result.offenders.len: result.offenders[i] = OffenderKey(fixed(bytes, i*32))

## Observe completed entries or immutable copied fields; failure contains its reason alone.
proc request(parts: seq[string]) =
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Source order is independent of production parsing; invalid sets must reject without sorting.
    var state = source(parts)
    let encoded = disputeStateEntry(state, policy)
    if encoded.error != DisputeStateError.None:
      echo ($encoded.error).toLowerAscii() # No default payload or partial counts after failure.
    else:
      # Destroy all mutable sources before observing returned entry bytes or their trie commitment.
      for kind in JudgmentSet:
        for i in 0..<state.reports[kind].len: state.reports[kind][i] = default(
            DisputeHash) # Output cannot alias caller sets.
      for i in 0..<state.offenders.len: state.offenders[i] = default(OffenderKey)
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # This root commits C(5) alone; it is not a complete JAM state root.
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(1)))
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    # Whole-parent validation must precede all retained child storage.
    var input = unhex(parts[4])
    let decoded = decodeDisputeState(input, policy)
    if decoded.error != DisputeStateError.None:
      echo ($decoded.error).toLowerAscii() # No owner or consumed cursor after rejection.
    else:
      for i in 0..<input.len: input[i] = 0 # Observe copied data after destroying caller wire.
      let owner = decoded.value.snapshot
      let info = disputeStateInfo(owner)
      doAssert info.error == DisputeStateError.None
      var output = $decoded.value.consumed
      # Owner-bound extraction retains each judgment set's exact membership.
      for kind in JudgmentSet:
        var bytes: seq[byte]
        for i in 0..<info.value.reports[kind]:
          let item = judgedReportAt(owner, kind, DisputeStateIndex(
              i)) # Extract fixed independent report identities.
          doAssert item.error == DisputeStateError.None
          bytes.add(array[32, byte](item.value))
        output.add(" " & $info.value.reports[kind] & ":" & hex(bytes))
      var bytes: seq[byte]
      # Keys stay bound to the offender set and cannot be extracted through the report API.
      for i in 0..<info.value.offenders:
        let item = stateOffenderAt(owner, DisputeStateIndex(i))
        doAssert item.error == DisputeStateError.None
        bytes.add(array[32, byte](item.value))
      echo output & " " & $info.value.offenders & ":" & hex(bytes)
  else: doAssert false # Unknown trusted operations cannot implicitly select another state schema.

# Every request releases its mutable inputs and private snapshot handles independently.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Ignore empty trusted transport lines.
