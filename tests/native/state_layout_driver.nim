## Trusted field adapter for independent GP state-key/node wire equations and fixed-value lifetime checks.
import std/[os, strutils]
import ../../src/[state_layout, bounded, composite]

# Select complete success before reading key, node, hash or consumed progress.
proc checked[T](parsed: StateLayoutResult[T]): T =
  doAssert parsed.error == StateLayoutError.None
  parsed.value

# Trusted hexadecimal transport becomes mutable caller input for copied-value lifetime tests.
proc unhex(text: string): seq[byte] =
  # Empty preimages/values need a single transport token.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 2*1024*1024
  result = newSeq[byte](text.len div 2)
  # Every byte can be overwritten after a decode/constructor returns.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Exact fixed field sources are independently named, never obtained from the production decoder.
proc fixed[N: static int](text: string): array[N, byte] =
  let bytes = unhex(text)
  doAssert bytes.len == N
  # Copy exactly the trusted schema's width; do not normalize/truncate key identities.
  for i in 0..<N: result[i] = bytes[i]

# Exact octet observations preserve leading zeroes and empty embedded logical values.
proc hex(bytes: openArray[byte]): string =
  # Empty logical values remain distinct from absent fields in the whitespace transport.
  if bytes.len == 0: return "-"
  # Preserve supplied octet order rather than reinterpreting fixed fields as host integers.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii())

# Fixed independent encoded nodes and their hashes are observed separately against the oracle.
proc emitted(parsed: StateLayoutResult[EncodedStateNode]) =
  # Failure must expose no encoded/default node or node identity.
  if parsed.error != StateLayoutError.None:
    echo ($parsed.error).toLowerAscii()
  else:
    # Hashing the returned canonical encoding also exercises the maintained native primitive composition.
    let identity = checked(hashStateNode(parsed.value))
    echo hex(array[64, byte](parsed.value)) & " " & hex(array[32, byte](identity))

# Read-only metadata fields are complete copies, with no fabricated full left-child hash or original hashed value.
proc observed(node: StateNodeInfo): string =
  case node.kind
  of StateNodeKind.Branch:
    # The partial left commitment is printed as such; its high bit is always zero.
    result = "B " & hex(array[32, byte](node.left)) & " " & hex(array[32, byte](node.right))
  of StateNodeKind.EmbeddedLeaf:
    # Logical inline bytes are separate from the canonical padding checked by the node decoder.
    result = "E " & hex(array[31, byte](node.embeddedKey)) & " " & $uint8(node.length) &
      " " & hex(node.embedded.toOpenArray(0, int(uint8(node.length))-1))
  of StateNodeKind.HashedLeaf:
    # A value hash is not reinterpreted as a child-node identity or recovered long-value bytes.
    result = "H " & hex(array[31, byte](node.hashedKey)) & " " & hex(array[32, byte](
        node.valueHash))
  let encoded = checked(encodeStateNode(node))
  result.add(" " & hex(array[64, byte](encoded)))

# Construct sources independently and observe decoded fields after destroying the original caller input.
proc request(parts: seq[string]) =
  case parts[0]
  of "C":
    # C(i) accepts an explicitly nominal chapter octet, not a natural sequence length.
    echo hex(array[31, byte](chapterKey(StateChapter(parseInt(parts[1])))))
  of "S":
    # C(i,s) uses exactly four little-endian service octets in their chapter/service positions.
    echo hex(array[31, byte](chapterServiceKey(StateChapter(parseInt(parts[1])), ServiceIndex(
        parseBiggestUInt(parts[2])))))
  of "K":
    # C(s,h) hashes the exact raw preimage under an explicit caller resource ceiling.
    var input = unhex(parts[3])
    let parsed = hashedServiceKey(ServiceIndex(parseBiggestUInt(parts[1])), input, ByteLimit(
        parseBiggestUInt(parts[2])))
    if parsed.error != StateLayoutError.None: echo ($parsed.error).toLowerAscii() # No default key on policy/backend failure.
    else:
      # A constructed key remains independent of the now-destroyed original hash preimage.
      for i in 0..<input.len: input[i] = 0
      echo hex(array[31, byte](parsed.value))
  of "B":
    # Complete child hashes construct a branch by replacing only the left hash's high bit.
    let node = encodeStateBranch(StateNodeHash(fixed[32](parts[1])), StateNodeHash(fixed[32](parts[2])))
    emitted(StateLayoutResult[EncodedStateNode](error: StateLayoutError.None, value: node))
  of "L":
    # Source leaf keys have exactly 31 octets; raw values choose inline/hash form at the 32/33 boundary.
    var value = unhex(parts[3])
    let parsed = encodeStateLeaf(StateKey(fixed[31](parts[1])), value, ByteLimit(parseBiggestUInt(
        parts[2])))
    # The returned node is a fixed independent value, even for the inline borrowed input path.
    for i in 0..<value.len: value[i] = 0
    emitted(parsed)
  of "D":
    # Complete input prefix decoding returns copied metadata and leaves unrelated suffix bytes to its caller.
    var input = unhex(parts[1])
    let parsed = decodeStateNode(input)
    if parsed.error != StateLayoutError.None: echo ($parsed.error).toLowerAscii() # No node or consumed count after failure.
    else:
      # Metadata and exact re-emission must survive destruction of all original input bytes.
      for i in 0..<input.len: input[i] = 0
      echo $parsed.value.consumed & " " & observed(parsed.value.node)
  of "HB":
    # Manually constructed nominal encodings cannot bypass canonical-node validation before hashing.
    let parsed = hashStateNode(EncodedStateNode(fixed[64](parts[1])))
    if parsed.error != StateLayoutError.None: echo ($parsed.error).toLowerAscii() # Failure publishes no digest.
    else: echo hex(array[32, byte](parsed.value)) # A complete canonical node identity is an independent fixed hash.
  of "MB":
    # Invalid partial commitments must be rejected rather than silently normalized into a different source.
    emitted(encodeStateNode(StateNodeInfo(kind: StateNodeKind.Branch, left: LeftChildCommitment(
        fixed[32](parts[1])),
      right: StateNodeHash(fixed[32](parts[2])))))
  of "ME":
    # Independent metadata sources test oversized lengths and nonzero logical-padding errors.
    emitted(encodeStateNode(StateNodeInfo(kind: StateNodeKind.EmbeddedLeaf, embeddedKey: StateKey(
        fixed[31](parts[1])),
      length: EmbeddedLength(parseInt(parts[2])), embedded: fixed[32](parts[3]))))
  of "MH":
    # A regular leaf can be re-emitted directly from key/value hash without claiming its long preimage is known.
    emitted(encodeStateNode(StateNodeInfo(kind: StateNodeKind.HashedLeaf, hashedKey: StateKey(fixed[
        31](parts[1])),
      valueHash: StateValueHash(fixed[32](parts[2])))))
  else: doAssert false # Unknown trusted operations cannot implicitly choose another protocol schema.

# Request-local arrays and sequences release after each complete independent observation.
for line in lines(paramStr(1)):
  # Empty trusted batch lines contain no protocol operation.
  if line.len > 0: request(line.splitWhitespace())
