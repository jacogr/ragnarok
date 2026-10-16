## Trusted source/observation adapter for independent authorization state equations.
import std/[os, strutils]
import ../../src/codec/[state_authorization, state_trie, bounded, assurances]

## Keep an empty byte source expressible as a single transport token.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty pools and malformed empty wire are distinct trusted inputs.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Preserve exact octet order rather than parsing identities as host integers.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Observe full raw bytes, including leading zeroes and empty source rows.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty row boundaries in observed output.
  # Each source hash keeps its exact 32-octet identity.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

## Build independent typed source rows directly from authored fixed bytes, never production decoder output.
proc rows(parts: seq[string]): seq[AuthorizerRow] =
  let count = parseInt(parts[5])
  doAssert parts.len == 6+count
  result = newSeq[AuthorizerRow](count)
  # Row lengths are deliberately independent of protocol shape, permitting invalid source tests.
  for i in 0..<count:
    let bytes = unhex(parts[6+i])
    doAssert bytes.len mod 32 == 0
    result[i] = newSeq[AuthorizerHash](bytes.len div 32)
    # Fixed identity fields are copied from the trusted source schema.
    for j in 0..<result[i].len:
      for k in 0..<32: result[i][j].bytes[k] = bytes[j*32+k] # Preserve per-core position and full bytes.

## Trusted policy values become distinct chain cardinality, aggregate hashes and byte ceilings.
proc config(parts: seq[string]): AuthorizationConfig =
  AuthorizationConfig(cores: CoreCount(parseBiggestUInt(parts[2])),
    maxHashes: ElementLimit(parseBiggestUInt(parts[3])), maxBytes: ByteLimit(parseBiggestUInt(parts[4])))

## Select complete successes and observe immutable snapshots only after caller/source destruction.
proc request(parts: seq[string]) =
  let kind = AuthorizationKind(parseInt(parts[1]))
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Independently constructed source arrays exercise entry encoding, not a decoder/encoder round trip.
    var source = rows(parts)
    let encoded = authorizationEntry(kind, source, policy)
    if encoded.error != AuthorizationError.None:
      echo ($encoded.error).toLowerAscii() # Failure exposes no entry/default payload.
    else:
      if parts[0] == "V":
        # Mutation of every source field after encoding must leave the entry unchanged.
        for i in 0..<source.len:
          for j in 0..<source[i].len: source[i][j] = default(AuthorizerHash) # No mutable row storage is retained.
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # Partial integration commits both chapters, using a separate deterministic fixed queue source.
        doAssert kind == AuthorizationKind.Pools
        var queues = newSeq[AuthorizerRow](source.len)
        # Every queue position gets distinct patterned source bytes, preserving core/position order.
        for i in 0..<queues.len:
          queues[i] = newSeq[AuthorizerHash](80)
          for j in 0..<80:
            for k in 0..<32: queues[i][j].bytes[k] = byte((
                i+j+k) mod 256) # Shared deterministic test-only pattern.
        let queue = authorizationEntry(AuthorizationKind.Queues, queues, policy)
        doAssert queue.error == AuthorizationError.None
        let root = stateTrieRoot([encoded.value, queue.value], StateTrieLimits(items: ElementLimit(2),
          perValue: ByteLimit(high(uint64)), totalValueBytes: ByteLimit(high(uint64)),
              nodes: TrieNodeLimit(1000)))
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root)) & " " & $root.value.nodes
  of "D":
    # Full input validation precedes immutable owned copies; suffixes remain outside the snapshot.
    var wire = unhex(parts[5])
    let decoded = decodeAuthorization(kind, wire, policy)
    if decoded.error != AuthorizationError.None:
      echo ($decoded.error).toLowerAscii() # No partial rows or consumed cursor on error.
    else:
      for i in 0..<wire.len: wire[i] = 0 # Observe data after destruction of all caller wire bytes.
      let owner = decoded.value.snapshot
      let cores = authorizationCores(owner)
      let observedKind = authorizationKind(owner)
      doAssert cores.error == AuthorizationError.None and observedKind.error ==
          AuthorizationError.None
      var output = $decoded.value.consumed & " " & $cores.value & " " & $ord(observedKind.value)
      # Owner-bound row counts preserve empty pools rather than flattening away their positions.
      for i in 0..<cores.value:
        let core = AuthorizationCoreIndex(i)
        let count = authorizerCount(owner, core)
        doAssert count.error == AuthorizationError.None
        var bytes: seq[byte]
        # Each extraction is a complete independent hash copy with explicit core/row ordinals.
        for j in 0..<count.value:
          let hash = authorizerAt(owner, core, AuthorizationIndex(j))
          doAssert hash.error == AuthorizationError.None
          bytes.add(hash.value.bytes)
        output.add(" " & $count.value & ":" & hex(bytes))
      echo output
  else: doAssert false # Unknown trusted operations cannot implicitly choose a state schema.

# Batch requests release their mutable source arrays and snapshot handles after each observation.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Blank trusted lines carry no operation.
