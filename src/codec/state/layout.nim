# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 state-key constructors and 64-byte trie-node layout, not trie construction/state
## serialization. See spec/state-layout.md; all outputs are fixed independent value copies with
## no caller-buffer mutation.
##
## Exposes nominal state keys, chapter/service key constructors, typed trie-node metadata and
## node encoding, decoding and hashing.

import ../[bounded, composite]
import ../../crypto/primitives

type
  StateChapter* = distinct uint8 ## Chapter namespace octet is distinct from a service identifier or raw integer.
  StateKey* = distinct array[31, byte] ## GP state serialization keys contain exactly 31 octets, not full 32-byte hashes.
  StateNodeHash* = distinct array[32, byte] ## Complete trie child/node identity; hashing a node is separate from the empty-trie zero identity rule.
  LeftChildCommitment* = distinct array[32, byte] ## A branch stores only the low 255 bits of its left child; this cannot implicitly become a complete hash.
  StateValueHash* = distinct array[32, byte] ## A regular leaf stores a value hash, not a child-node identity or the original long value.
  EncodedStateNode* = distinct array[64, byte] ## Every encoded branch or leaf owns its entire canonical 64-octet node representation.
  EmbeddedLength* = distinct uint8 ## Embedded logical byte count must validate within 0..32 before any field/array use.
  StateLayoutError* {.pure.} = enum ## Default/failure alternatives expose only reasons, never keys, nodes, hashes or progress.
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, BackendFailure
  StateLayoutResult*[T] = object ## Success alone contains a complete independent fixed value.
    case status: StateLayoutError
    of None:
      # Select successful validation before reading any application field or completed extent.
      completed: T
    else:
      # Default/failure contains no usable data or cursor.
      discard
  StateNodeKind* {.pure.} = enum ## Node metadata alternatives expose only fields actually committed by that node format.
    Branch, EmbeddedLeaf, HashedLeaf
  StateNodeInfo* = object ## Every metadata field is a fixed value copy; no pointer, span, heap owner or reconstructed long value escapes.
    case nodeKind: StateNodeKind
    of Branch:
      # Left commitment has a zero high bit; the lost original high bit is deliberately not fabricated.
      branchLeft: LeftChildCommitment
      branchRight: StateNodeHash
    of EmbeddedLeaf:
      # Embedded leaf values are at most 32 bytes; remaining copied storage is canonical zero padding.
      inlineKey: StateKey
      inlineLength: EmbeddedLength
      inlineBytes: array[32, byte]
    of HashedLeaf:
      # A long value's hash cannot be confused with an embedded value or a complete child hash.
      regularKey: StateKey
      regularHash: StateValueHash
  StateNodeRead* = object ## A successful decoder consumes one canonical fixed node prefix, leaving unrelated suffixes to its caller.
    node*: StateNodeInfo
    consumed*: int

func error*[T](value: StateLayoutResult[T]): StateLayoutError =
  ## Failure reasons remain readable without authorizing any completed key, node, metadata or progress.
  value.status

func value*[T](value: StateLayoutResult[T]): T {.inline, requires: value.status ==
    StateLayoutError.None.} =
  ## Completed fields require the selected success alternative in optimized builds too.
  value.completed

func kind*(node: StateNodeInfo): StateNodeKind =
  ## Metadata tags are read-only; default metadata is the existing all-zero branch.
  node.nodeKind

func left*(node: StateNodeInfo): LeftChildCommitment {.inline, requires: node.nodeKind ==
    StateNodeKind.Branch.} =
  ## Return an independent left copy only from its selected Branch alternative.
  node.branchLeft

func right*(node: StateNodeInfo): StateNodeHash {.inline, requires: node.nodeKind ==
    StateNodeKind.Branch.} =
  ## Return an independent right copy only from its selected Branch alternative.
  node.branchRight

func embeddedKey*(node: StateNodeInfo): StateKey {.inline, requires: node.nodeKind ==
    StateNodeKind.EmbeddedLeaf.} =
  ## Return an independent embeddedKey copy only from its selected EmbeddedLeaf alternative.
  node.inlineKey

func length*(node: StateNodeInfo): EmbeddedLength {.inline, requires: node.nodeKind ==
    StateNodeKind.EmbeddedLeaf.} =
  ## Return an independent length copy only from its selected EmbeddedLeaf alternative.
  node.inlineLength

func embedded*(node: StateNodeInfo): array[32, byte] {.inline, requires: node.nodeKind ==
    StateNodeKind.EmbeddedLeaf.} =
  ## Return an independent embedded copy only from its selected EmbeddedLeaf alternative.
  node.inlineBytes

func hashedKey*(node: StateNodeInfo): StateKey {.inline, requires: node.nodeKind ==
    StateNodeKind.HashedLeaf.} =
  ## Return an independent hashedKey copy only from its selected HashedLeaf alternative.
  node.regularKey

func valueHash*(node: StateNodeInfo): StateValueHash {.inline, requires: node.nodeKind ==
    StateNodeKind.HashedLeaf.} =
  ## Return an independent valueHash copy only from its selected HashedLeaf alternative.
  node.regularHash

func branchNodeInfo*(left: LeftChildCommitment, right: StateNodeHash): StateNodeInfo =
  ## Construct copied branch source metadata; encodeStateNode validates its partial commitment before emission.
  StateNodeInfo(nodeKind: Branch, branchLeft: left, branchRight: right)

func embeddedNodeInfo*(key: StateKey, length: EmbeddedLength, bytes: array[32,
    byte]): StateNodeInfo =
  ## Construct copied embedded source metadata; encodeStateNode validates length and every unused padding byte.
  StateNodeInfo(nodeKind: EmbeddedLeaf, inlineKey: key, inlineLength: length, inlineBytes: bytes)

func hashedNodeInfo*(key: StateKey, hash: StateValueHash): StateNodeInfo =
  ## Construct copied regular source metadata without claiming possession of the long value's preimage.
  StateNodeInfo(nodeKind: HashedLeaf, regularKey: key, regularHash: hash)

proc chapterKey*(chapter: StateChapter): StateKey {.raises: [].} =
  ## Construct C(i): chapter octet followed by thirty zero octets, with no natural-length prefix.
  var bytes = default(array[31, byte])
  bytes[0] = byte(chapter)
  StateKey(bytes)

proc chapterServiceKey*(chapter: StateChapter, service: ServiceIndex): StateKey {.raises: [].} =
  ## Construct C(i,s): interleave little-endian E4 service octets with zeroes after the chapter octet.
  var bytes = default(array[31, byte])
  bytes[0] = byte(chapter)
  let number = uint32(service)
  # Each service octet occupies positions 1,3,5,7; the remaining key positions stay zero.
  for i in 0..<4: bytes[1+2*i] = byte((number shr (8*i)) and 255)
  StateKey(bytes)

proc hashedServiceKey*(service: ServiceIndex, preimage: openArray[byte],
    limit: ByteLimit): StateLayoutResult[StateKey] =
  ## Construct C(s,h) using the exact raw preimage h, whose semantic namespace/domain prefix belongs to its caller.
  # Caller resource policy precedes hashing borrowed bytes; no length discriminator is added to h.
  if uint64(preimage.len) > uint64(limit): return StateLayoutResult[StateKey](
      status: StateLayoutError.LimitExceeded)
  let hashed = blake2b256(preimage)
  # Never expose a default key or silently substitute a zero hash after backend failure.
  if hashed.error != CryptoError.None: return StateLayoutResult[StateKey](
      status: StateLayoutError.BackendFailure)
  let digest = array[32, byte](hashed.value)
  var bytes = default(array[31, byte])
  let number = uint32(service)
  # First four digest octets alternate with the little-endian service octets.
  for i in 0..<4:
    bytes[2*i] = byte((number shr (8*i)) and 255)
    bytes[2*i+1] = digest[i]
  # The key keeps digest octets 4..26; the final five digest octets are outside this 31-byte layout.
  for i in 4..<27: bytes[i+4] = digest[i]
  StateLayoutResult[StateKey](status: StateLayoutError.None, completed: StateKey(bytes))

proc encodeStateBranch*(left, right: StateNodeHash): EncodedStateNode {.raises: [].} =
  ## Encode B(left,right), explicitly discarding only the original left hash's most-significant bit.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  var bytes = default(array[64, byte])
  # Branch discriminator zero replaces the lost high bit; it is not general C.1 bitstring packing.
  for i in 0..<32:
    bytes[i] = a[i]
    bytes[32+i] = b[i]
  bytes[0] = bytes[0] and 127
  EncodedStateNode(bytes)

proc encodeStateLeaf*(key: StateKey, value: openArray[byte],
    limit: ByteLimit): StateLayoutResult[EncodedStateNode] =
  ## Encode L(key,value): embed 0..32 raw octets or commit a longer value with Blake2b-256.
  # Structural value policy is explicit and applies before reading/hashing any borrowed value bytes.
  if uint64(value.len) > uint64(limit): return StateLayoutResult[EncodedStateNode](
      status: StateLayoutError.LimitExceeded)
  var bytes = default(array[64, byte])
  let identity = array[31, byte](key)
  # Both leaf forms store all 31 key octets at the same exact offset.
  for i in 0..<31: bytes[1+i] = identity[i]
  # Embedded header 10xxxxxx contains the byte length and zero-pads the unused value suffix.
  if value.len <= 32:
    bytes[0] = 128 or byte(value.len)
    # Fresh fixed storage already has canonical zero padding beyond the logical value length.
    for i in 0..<value.len: bytes[32+i] = value[i]
  else:
    # Regular leaves have exactly header c0 and the complete value digest, without a byte-count field.
    bytes[0] = 192
    let hashed = blake2b256(value)
    if hashed.error != CryptoError.None: return StateLayoutResult[EncodedStateNode](
        status: StateLayoutError.BackendFailure) # No partial node on failure.
    let digest = array[32, byte](hashed.value)
    # Store a value hash, not a second node hash or the original long value.
    for i in 0..<32: bytes[32+i] = digest[i]
  StateLayoutResult[EncodedStateNode](status: StateLayoutError.None, completed: EncodedStateNode(bytes))

proc decodeStateNode*(input: openArray[byte]): StateLayoutResult[StateNodeRead] {.raises: [].} =
  ## Decode one complete node prefix into independently copied metadata; reject reserved headers and nonzero embedded padding.
  # All node formats are fixed at 64 octets; no tag or metadata escapes a shorter input.
  if input.len < 64: return StateLayoutResult[StateNodeRead](status: StateLayoutError.Truncated)
  var first = default(array[32, byte])
  var second = default(array[32, byte])
  # Copy both halves before selecting semantic roles; neither output references input storage.
  for i in 0..<32:
    first[i] = input[i]
    second[i] = input[32+i]
  # A zero high bit denotes a branch, whose left half is a truncated commitment rather than a recoverable complete hash.
  if input[0] < 128:
    return StateLayoutResult[StateNodeRead](status: StateLayoutError.None, completed: StateNodeRead(
      node: StateNodeInfo(nodeKind: StateNodeKind.Branch, branchLeft: LeftChildCommitment(first),
          branchRight: StateNodeHash(second)), consumed: 64))
  var key = default(array[31, byte])
  # Leaf identity bytes follow the header in both embedded and regular leaves.
  for i in 0..<31: key[i] = input[i+1]
  # Embedded values have the low six header bits as their length, but only 0..32 is defined by L.
  if input[0] < 192:
    let length = int(input[0] and 63)
    if length > 32: return StateLayoutResult[StateNodeRead](
        status: StateLayoutError.NonCanonical) # Lengths 33..63 have no embedded encoder image.
    # Padding is part of the canonical 64-byte node and must not carry uncommitted extra value bytes.
    for i in length..<32:
      if second[i] != 0: return StateLayoutResult[StateNodeRead](
          status: StateLayoutError.NonCanonical) # Nonzero unused suffix cannot be normalized silently.
    return StateLayoutResult[StateNodeRead](status: StateLayoutError.None, completed: StateNodeRead(
      node: StateNodeInfo(nodeKind: StateNodeKind.EmbeddedLeaf, inlineKey: StateKey(key),
          inlineLength: EmbeddedLength(length), inlineBytes: second), consumed: 64))
  # The six reserved bits of a hashed leaf are exactly zero; c1..ff are not alternate regular leaf headers.
  if input[0] != 192: return StateLayoutResult[StateNodeRead](status: StateLayoutError.NonCanonical)
  StateLayoutResult[StateNodeRead](status: StateLayoutError.None, completed: StateNodeRead(
    node: StateNodeInfo(nodeKind: StateNodeKind.HashedLeaf, regularKey: StateKey(key),
        regularHash: StateValueHash(second)), consumed: 64))

proc encodeStateNode*(node: StateNodeInfo): StateLayoutResult[EncodedStateNode] {.raises: [].} =
  ## Re-emit copied node metadata without inventing the missing left-hash bit or requiring a regular leaf's original value.
  var bytes = default(array[64, byte])
  case node.kind
  of Branch:
    # Branch metadata must already be a canonical partial commitment with its high bit zero.
    let left = array[32, byte](node.left)
    if left[0] >= 128: return StateLayoutResult[EncodedStateNode](
        status: StateLayoutError.NonCanonical) # Never silently mask invalid decoded-style metadata.
    let right = array[32, byte](node.right)
    # Preserve exactly the committed 255 left bits and all 256 right bits.
    for i in 0..<32:
      bytes[i] = left[i]
      bytes[32+i] = right[i]
  of EmbeddedLeaf:
    # Embedded metadata must fit its logical domain and already contain canonical unused padding.
    let length = int(uint8(node.length))
    if length > 32: return StateLayoutResult[EncodedStateNode](
        status: StateLayoutError.NonCanonical) # Invalid sources publish no node.
    for i in length..<32:
      if node.embedded[i] != 0: return StateLayoutResult[EncodedStateNode](
          status: StateLayoutError.NonCanonical) # Preflight every suffix byte before success.
    bytes[0] = 128 or byte(length)
    let key = array[31, byte](node.embeddedKey)
    # Commit only fixed source copies; there is no borrowed source/destination alias to manage.
    for i in 0..<31: bytes[1+i] = key[i]
    for i in 0..<32: bytes[32+i] = node.embedded[i] # The already-validated padding remains canonical.
  of HashedLeaf:
    # A regular leaf can be re-emitted from its committed value hash without claiming access to the original value.
    bytes[0] = 192
    let key = array[31, byte](node.hashedKey)
    let digest = array[32, byte](node.valueHash)
    # Preserve each fixed field's exact identity and octet order.
    for i in 0..<31: bytes[1+i] = key[i]
    for i in 0..<32: bytes[32+i] = digest[i] # The digest is not decoded as embedded bytes.
  StateLayoutResult[EncodedStateNode](status: StateLayoutError.None, completed: EncodedStateNode(bytes))

proc hashStateNode*(node: EncodedStateNode): StateLayoutResult[StateNodeHash] =
  ## Hash a canonical encoded node using raw Blake2b-256; empty-trie identity and trie traversal are separate responsibilities.
  let bytes = array[64, byte](node)
  let checked = decodeStateNode(bytes)
  # Constructing a nominal encoded value manually must not bypass header/padding canonicality.
  if checked.error != StateLayoutError.None: return StateLayoutResult[StateNodeHash](
      status: checked.error)
  let hashed = blake2b256(bytes)
  if hashed.error != CryptoError.None: return StateLayoutResult[StateNodeHash](
      status: StateLayoutError.BackendFailure) # Failed native hashing exposes no node identity.
  StateLayoutResult[StateNodeHash](status: StateLayoutError.None, completed: StateNodeHash(array[32,
      byte](hashed.value)))
