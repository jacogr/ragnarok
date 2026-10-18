# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Focused state-layout fixed-copy, partial-commitment and selected-alternative guard regressions.
import std/[assertions, syncio]
import ../../../src/codec/[state_layout, bounded, composite]

# Only complete success authorizes access to node metadata, hashes or keys.
proc checked[T](parsed: StateLayoutResult[T]): T =
  assert parsed.error == StateLayoutError.None
  parsed.value

var keyBytes = default(array[31, byte])
keyBytes[30] = 255
let key = StateKey(keyBytes)
var input = @[1'u8, 2, 3]
let node = checked(encodeStateLeaf(key, input, ByteLimit(3)))
input[0] = 255
var wire = array[64, byte](node)
let parsed = checked(decodeStateNode(wire))
# All copied metadata and fixed results survive caller-input/source mutation.
for i in 0..<wire.len: wire[i] = 0
assert parsed.node.kind == StateNodeKind.EmbeddedLeaf
let info = parsed.node
var copied = info.embedded
copied[0] = 255
assert info.embedded[0] == 1
assert parsed.node.embedded[0] == 1
assert array[31, byte](parsed.node.embeddedKey)[30] == 255
var a = default(array[32, byte])
var b = default(array[32, byte])
a[0] = 128
let first = encodeStateBranch(StateNodeHash(a), StateNodeHash(b))
a[0] = 0
let second = encodeStateBranch(StateNodeHash(a), StateNodeHash(b))
assert array[64, byte](first) == array[64, byte](second)
let branch = checked(decodeStateNode(array[64, byte](first))).node
assert array[32, byte](branch.left)[0] == 0
# Losing the left high bit is intentional B encoding, while metadata claiming to be already truncated must be canonical.
a[0] = 128
assert encodeStateNode(branchNodeInfo(LeftChildCommitment(a), StateNodeHash(b))).error ==
    StateLayoutError.NonCanonical
let constructed = chapterServiceKey(StateChapter(255), ServiceIndex(0x01020304))
let bytes = array[31, byte](constructed)
# Observe each fixed octet without an allocating array slice.
for i, expected in [255'u8, 4, 0, 3, 0, 2, 0, 1, 0]: assert bytes[i] == expected
# Failed/default results and every inactive metadata field run in isolated processes in the trial runner.
assert decodeStateNode(@[128'u8]).error == StateLayoutError.Truncated
let absent = default(StateLayoutResult[StateKey])
assert absent.error == StateLayoutError.Uninitialized
let long = checked(encodeStateLeaf(key, newSeq[byte](33), ByteLimit(33)))
let regular = checked(decodeStateNode(array[64, byte](long))).node
assert regular.kind == StateNodeKind.HashedLeaf
var regularHash = array[32, byte](regular.valueHash)
regularHash[0] = regularHash[0] xor 255
assert regularHash != array[32, byte](regular.valueHash)
echo "Nimony state layout: fixed-copy lifetimes, partial left commitments and copied metadata passed"

# Test-only native refusal flags are linked solely into this selftest, never the production corpus adapter.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
fail(1)
# Each hashing composition translates primitive refusal into a typed layout failure without publishing default bytes.
assert hashedServiceKey(ServiceIndex(0), [], ByteLimit(0)).error == StateLayoutError.BackendFailure
assert encodeStateLeaf(key, newSeq[byte](33), ByteLimit(33)).error ==
    StateLayoutError.BackendFailure
assert hashStateNode(first).error == StateLayoutError.BackendFailure
# Resource and structural validation must precede native hashing, even when its backend would refuse.
assert hashedServiceKey(ServiceIndex(0), [1'u8], ByteLimit(0)).error ==
    StateLayoutError.LimitExceeded
assert encodeStateLeaf(key, newSeq[byte](33), ByteLimit(32)).error == StateLayoutError.LimitExceeded
assert encodeStateLeaf(key, [], ByteLimit(0)).error == StateLayoutError.None
assert encodeStateNode(embeddedNodeInfo(key, EmbeddedLength(33), default(array[32, byte]))).error ==
  StateLayoutError.NonCanonical
fail(0)
assert hashStateNode(first).error == StateLayoutError.None
# Source factories copy supplied fields, and getter copies cannot rewrite their original node metadata.
var source = default(array[32, byte])
source[0] = 7
let inlineSource = embeddedNodeInfo(key, EmbeddedLength(1), source)
source[0] = 8
assert inlineSource.embedded[0] == 7
let inlineWire = checked(encodeStateNode(inlineSource))
assert array[64, byte](inlineWire)[32] == 7
var rightCopy = array[32, byte](branch.right)
rightCopy[0] = rightCopy[0] xor 255
assert rightCopy != array[32, byte](branch.right)
var leftCopy = array[32, byte](branch.left)
leftCopy[1] = leftCopy[1] xor 255
assert leftCopy != array[32, byte](branch.left)
var keyCopy = array[31, byte](regular.hashedKey)
keyCopy[0] = keyCopy[0] xor 255
assert keyCopy != array[31, byte](regular.hashedKey)
echo "Nimony state layout: backend failure/recovery, policy precedence and source/getter copies passed"
