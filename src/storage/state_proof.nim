# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded single-key GP lookup proofs bind authenticated presence/absence to a caller-trusted root.
## Proofs are detached local transport, not a network format or a source of chain/finality trust.
import std/assertions
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../codec/bounded as codec_bounded

type
  StateProof* = object ## Untrusted stable borrowed input; raw value bytes are used only for proven presence.
    nodes*: seq[EncodedStateNode]
    value*: seq[byte]
  StateProofLimits* = object ## Caller policy can tighten the fixed 249-node path bound and raw-value ceiling.
    nodes*: ElementLimit
    valueBytes*: ByteLimit
  StateProofError* {.pure.} = enum ## Incomplete evidence never becomes authenticated absence.
    Uninitialized, None, LimitExceeded, InvalidProof, IncompleteProof, ValueMismatch, BackendFailure
  StateLookupKind* {.pure.} = enum ## Both alternatives are authenticated; unavailable data is a proof failure.
    Present, Absent
  LookupData = ref object ## Private immutable owned result retains the exact root/key and only validated bytes.
    root: StateRoot
    key: StateKey
    kind: StateLookupKind
    bytes: seq[byte]
  VerifiedStateLookup* = object ## Cheap copies retain one immutable root-bound lookup, never a partial full-state map.
    owner: nil LookupData
  StateProofResult*[T] = object ## Default/failure alternatives contain only their reason.
    case status: StateProofError
    of None:
      completed: T
    else:
      discard

func error*[T](outcome: StateProofResult[T]): StateProofError =
  ## Read a reason without authorizing extraction of incomplete or invalid lookup evidence.
  outcome.status
func value*[T](outcome: StateProofResult[T]): T {.inline,
    requires: outcome.status == StateProofError.None.} =
  ## Only a selected success grants access to its immutable completed lookup.
  outcome.completed
proc root*(lookup: VerifiedStateLookup): StateRoot {.requires: lookup.owner != nil.} =
  ## Return the exact trusted-root argument, never a commitment calculated from partial state.
  let owner = lookup.owner
  assert owner != nil
  owner.root
proc key*(lookup: VerifiedStateLookup): StateKey {.requires: lookup.owner != nil.} =
  ## Bind retained evidence to its exact original serialized query key.
  let owner = lookup.owner
  assert owner != nil
  owner.key
proc kind*(lookup: VerifiedStateLookup): StateLookupKind {.requires: lookup.owner != nil.} =
  ## Successful absence is distinct from an incomplete proof and a present empty value.
  let owner = lookup.owner
  assert owner != nil
  owner.kind
proc bytes*(lookup: VerifiedStateLookup): seq[byte] {.requires: lookup.owner != nil and
    lookup.owner.kind == StateLookupKind.Present.} =
  ## Copy only authenticated present bytes; an absent result has no value storage to read.
  let owner = lookup.owner
  assert owner != nil and owner.kind == StateLookupKind.Present
  result = newSeq[byte](owner.bytes.len)
  for index in 0..<owner.bytes.len: result[index] = owner.bytes[
      index] # Mutable copies cannot change the retained evidence.

func one(key: StateKey, depth: int): bool =
  ## Callers prove depth<248 before reading a query's MSB-first direction bit.
  let raw = array[31, byte](key)
  (raw[depth div 8] and byte(128 shr (depth mod 8))) != 0
func sharesPrefix(left, right: StateKey, depth: int): bool =
  ## A terminal singleton must belong to every already traversed query partition.
  for bit in 0..<depth:
    if one(left, bit) != one(right, bit): return false # Full-key absence cannot use a leaf outside the path.
  true
func equalDigest(left, right: array[32, byte], partial: bool): bool =
  ## Only a left edge discards the high bit; root and right identities remain complete.
  for index in 0..<32:
    let mask = if partial and index == 0: 127'u8 else: 255'u8
    if (left[index] and mask) != (right[index] and mask): return false
  true
proc absent(root: StateRoot, key: StateKey, rawBytes: int): StateProofResult[VerifiedStateLookup] =
  ## Unused payloads are noncanonical; absence owns only its trusted binding and outcome.
  if rawBytes != 0:
    return StateProofResult[VerifiedStateLookup](status: StateProofError.InvalidProof)
  StateProofResult[VerifiedStateLookup](status: StateProofError.None,
    completed: VerifiedStateLookup(owner: LookupData(root: root, key: key,
        kind: StateLookupKind.Absent)))

proc verifyStateProof*(root: StateRoot, key: StateKey, proof: StateProof,
    limits: StateProofLimits): StateProofResult[VerifiedStateLookup] =
  ## Verify bounded canonical root-to-terminal evidence; trusted-root provenance remains the caller's duty.
  ## No output owner is allocated until every path/value check succeeds. Allocation failure is fail-stop.
  if proof.nodes.len > 249 or uint64(proof.nodes.len) > uint64(limits.nodes) or
      uint64(proof.value.len) > uint64(limits.valueBytes):
    return StateProofResult[VerifiedStateLookup](status: StateProofError.LimitExceeded) # Bound work before decoding/hashing.
  var expected = array[32, byte](root)
  let zero = default(array[32, byte])
  if expected == zero:
    if proof.nodes.len != 0:
      return StateProofResult[VerifiedStateLookup](
          status: StateProofError.InvalidProof) # Empty roots cannot consume a node.
    return absent(root, key, proof.value.len)
  if proof.nodes.len == 0:
    return StateProofResult[VerifiedStateLookup](status: StateProofError.IncompleteProof) # No local node is not protocol absence.
  var partial = false
  var depth = 0
  for index, encoded in proof.nodes:
    let raw = array[64, byte](encoded)
    let decoded = decodeStateNode(raw)
    if decoded.error != StateLayoutError.None:
      return StateProofResult[VerifiedStateLookup](
          status: StateProofError.InvalidProof) # Reject headers and nonzero inline padding.
    let node = decoded.value.node
    let digest = hashStateNode(encoded)
    if digest.error != StateLayoutError.None:
      return StateProofResult[VerifiedStateLookup](
          status: StateProofError.BackendFailure) # Primitive refusal cannot authenticate anything.
    if not equalDigest(array[32, byte](digest.value), expected, partial):
      return StateProofResult[VerifiedStateLookup](
          status: StateProofError.InvalidProof) # Compare exactly the bits this edge commits.
    if node.kind == StateNodeKind.Branch:
      if depth >= 248:
        return StateProofResult[VerifiedStateLookup](
            status: StateProofError.InvalidProof) # Prove key-bit bounds before access.
      if one(key, depth):
        expected = array[32, byte](node.right)
        partial = false # The right edge retains all 256 child digest bits.
      else:
        expected = array[32, byte](node.left)
        partial = true # LeftChildCommitment never fabricates the discarded high bit.
      inc depth
      if expected == zero:
        if index != proof.nodes.len-1:
          return StateProofResult[VerifiedStateLookup](
              status: StateProofError.InvalidProof) # Nothing may follow an empty child.
        return absent(root, key, proof.value.len)
    else:
      if index != proof.nodes.len-1:
        return StateProofResult[VerifiedStateLookup](
            status: StateProofError.InvalidProof) # A terminal leaf cannot hide trailing evidence.
      let leafKey = if node.kind == StateNodeKind.EmbeddedLeaf: node.embeddedKey else: node.hashedKey
      if not sharesPrefix(leafKey, key, depth):
        return StateProofResult[VerifiedStateLookup](
            status: StateProofError.InvalidProof) # Different-key absence must remain inside its subtree.
      if array[31, byte](leafKey) != array[31, byte](key): return absent(root, key, proof.value.len)
      let leaf = encodeStateLeaf(key, proof.value, limits.valueBytes)
      if leaf.error == StateLayoutError.BackendFailure:
        return StateProofResult[VerifiedStateLookup](
            status: StateProofError.BackendFailure) # Long values require their real preimage hash.
      if leaf.error != StateLayoutError.None or array[64, byte](leaf.value) != raw:
        return StateProofResult[VerifiedStateLookup](
            status: StateProofError.ValueMismatch) # One canonical inline/hashed encoding only.
      var owned = newSeq[byte](proof.value.len)
      for offset, octet in proof.value: owned[offset] = octet # Input mutation after return cannot change authenticated bytes.
      return StateProofResult[VerifiedStateLookup](status: StateProofError.None,
        completed: VerifiedStateLookup(owner: LookupData(root: root, key: key,
          kind: StateLookupKind.Present, bytes: owned)))
  StateProofResult[VerifiedStateLookup](status: StateProofError.IncompleteProof) # A final nonempty child still needs its node.
