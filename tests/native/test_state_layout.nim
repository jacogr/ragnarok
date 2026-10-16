## Focused state-layout fixed-copy, partial-commitment and selected-alternative guard regressions.
import ../../src/[state_layout, bounded, composite]

# Only complete success authorizes access to node metadata, hashes or keys.
proc checked[T](parsed: StateLayoutResult[T]): T =
  doAssert parsed.error == StateLayoutError.None
  parsed.value

var keyBytes: array[31, byte]
keyBytes[30] = 255
let key = StateKey(keyBytes)
var input = @[1'u8, 2, 3]
let node = checked(encodeStateLeaf(key, input, ByteLimit(3)))
input[0] = 255
var wire = array[64, byte](node)
let parsed = checked(decodeStateNode(wire))
# All copied metadata and fixed results survive caller-input/source mutation.
for i in 0..<wire.len: wire[i] = 0
doAssert parsed.node.kind == StateNodeKind.EmbeddedLeaf
var info = parsed.node
info.embedded[0] = 255
doAssert parsed.node.embedded[0] == 1
doAssert array[31, byte](parsed.node.embeddedKey)[30] == 255
var a, b: array[32, byte]
a[0] = 128
let first = encodeStateBranch(StateNodeHash(a), StateNodeHash(b))
a[0] = 0
let second = encodeStateBranch(StateNodeHash(a), StateNodeHash(b))
doAssert array[64, byte](first) == array[64, byte](second)
let branch = checked(decodeStateNode(array[64, byte](first))).node
doAssert array[32, byte](branch.left)[0] == 0
# Losing the left high bit is intentional B encoding, while metadata claiming to be already truncated must be canonical.
a[0] = 128
doAssert encodeStateNode(StateNodeInfo(kind: StateNodeKind.Branch, left: LeftChildCommitment(a),
    right: StateNodeHash(b))).error == StateLayoutError.NonCanonical
let constructed = chapterServiceKey(StateChapter(255), ServiceIndex(0x01020304))
let bytes = array[31, byte](constructed)
doAssert bytes[0..8] == @[255'u8, 4, 0, 3, 0, 2, 0, 1, 0]
var guarded = false
try:
  # Failed results contain no fabricated node or consumed cursor.
  discard decodeStateNode(@[128'u8]).value.consumed
except FieldDefect:
  # Checked optimized builds retain the selected-success field guard.
  guarded = true
doAssert guarded
guarded = false
try:
  # A regular leaf stores a hash and must not expose an inactive embedded length/value.
  let long = checked(encodeStateLeaf(key, newSeq[byte](33), ByteLimit(33)))
  discard checked(decodeStateNode(array[64, byte](long))).node.length
except FieldDefect:
  # Copied node metadata retains its own selected-alternative guard too.
  guarded = true
doAssert guarded
var absent: StateLayoutResult[StateKey]
guarded = false
try:
  # Default results must not be readable as a fabricated all-zero state key.
  discard absent.value
except FieldDefect:
  # This checks default failure independently of malformed decoding.
  guarded = true
doAssert guarded
echo "Nim state layout: fixed-copy lifetimes, partial left commitments and variant guards passed"
