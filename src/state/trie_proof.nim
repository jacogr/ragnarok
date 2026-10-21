# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded immutable path witnesses for the pinned state trie. Capture validates structure only;
## independently supplied roots and keys grant lookup authority through a separate verifier.
import ../codec/[bounded, state_layout, state_trie]

type
  StateProofLimits* = object ## Independent ceilings apply before path/value copying or hashing.
    nodes*: ElementLimit
    valueBytes*: ByteLimit
  StateProofError* {.pure.} = enum ## Failure alternatives never expose a proof prefix or lookup payload.
    Uninitialized, None, LimitExceeded, InvalidProof, InvalidIndex, RootMismatch,
    KeyMismatch, BackendFailure, MissingValue, StoreFailure
  ProofData = ref object ## Private acyclic ownership freezes copied canonical nodes and supplied bytes.
    nodes: seq[EncodedStateNode]
    value: seq[byte]
  StateProof* = object ## An unverified path witness is deliberately distinct from a verified lookup.
    data: nil ProofData
  VerifiedStateLookup* = object ## Immutable verified evidence is bound to the independently supplied root and key.
    proof: StateProof
    rootIdentity: StateRoot
    keyIdentity: StateKey
    found: bool
  StateProofResult*[T] = object ## Success alone owns a complete checked result.
    case status: StateProofError
    of None:
      completed: T
    else:
      discard                   # Default and failure retain only their reason.

func error*[T](outcome: StateProofResult[T]): StateProofError =
  ## Inspect a reason without authorizing extraction.
  outcome.status
func value*[T](outcome: StateProofResult[T]): T {.inline,
    requires: outcome.status == StateProofError.None.} =
  ## Require explicit success even in optimized checked builds.
  outcome.completed
func valid*(proof: StateProof): bool =
  ## Structural capture alone never establishes commitment or membership.
  proof.data != nil
func len*(proof: StateProof): int =
  ## Defaults have no captured nodes and cannot become empty-trie evidence.
  let data = proof.data
  if data == nil: 0 else: data.nodes.len
proc nodeAt*(proof: StateProof, index: int): StateProofResult[EncodedStateNode] =
  ## Copy one fixed node, with invalid owner/index refusal instead of silent defaults.
  let data = proof.data
  if data == nil:
    return StateProofResult[EncodedStateNode](status: StateProofError.Uninitialized)
  if index < 0 or index >= data.nodes.len:
    return StateProofResult[EncodedStateNode](status: StateProofError.InvalidIndex)
  StateProofResult[EncodedStateNode](status: StateProofError.None,
    completed: data.nodes[index])
proc suppliedValue*(proof: StateProof): StateProofResult[seq[byte]] =
  ## Return detached unverified bytes; callers must not interpret them as authenticated state.
  let data = proof.data
  if data == nil:
    return StateProofResult[seq[byte]](status: StateProofError.Uninitialized)
  var copied = newSeq[byte](data.value.len)
  for i, octet in data.value:
    copied[i] = octet # No mutable backing storage escapes the immutable owner.
  StateProofResult[seq[byte]](status: StateProofError.None, completed: copied)
proc captureStateProof*(nodes: openArray[EncodedStateNode], supplied: openArray[byte],
    limits: StateProofLimits): StateProofResult[StateProof] =
  ## Bound and validate every canonical node before publishing one immutable witness.
  if nodes.len > 249 or uint64(nodes.len) > uint64(limits.nodes) or
      uint64(supplied.len) > uint64(limits.valueBytes):
    return StateProofResult[StateProof](status: StateProofError.LimitExceeded)
  for i, node in nodes:
    # Each nonterminal is a branch; a terminal leaf or empty selected edge ends the path.
    let decoded = decodeStateNode(array[64, byte](node))
    if decoded.error != StateLayoutError.None:
      return StateProofResult[StateProof](status: StateProofError.InvalidProof)
    if i < nodes.len - 1 and decoded.value.node.kind != StateNodeKind.Branch:
      return StateProofResult[StateProof](status: StateProofError.InvalidProof)
    if decoded.value.node.kind == StateNodeKind.Branch:
      # A terminal branch may witness an empty selected edge, but no branch exists below bit 247.
      if i >= 248:
        return StateProofResult[StateProof](status: StateProofError.InvalidProof)
      if array[32, byte](decoded.value.node.left) == default(array[32, byte]) and
          array[32, byte](decoded.value.node.right) == default(array[32, byte]):
        return StateProofResult[StateProof](status: StateProofError.InvalidProof)
  var copiedNodes = newSeq[EncodedStateNode](nodes.len)
  for i, node in nodes:
    copiedNodes[i] = node # Fixed node copies preserve exact canonical bytes.
  var copiedValue = newSeq[byte](supplied.len)
  for i, octet in supplied:
    copiedValue[i] = octet # Capture never shares mutable caller sequences.
  StateProofResult[StateProof](status: StateProofError.None,
    completed: StateProof(data: ProofData(nodes: copiedNodes, value: copiedValue)))

func valid*(lookup: VerifiedStateLookup): bool =
  ## A default lookup never grants access, even if all-zero identities were supplied elsewhere.
  lookup.proof.valid
func present*(lookup: VerifiedStateLookup): bool {.requires: lookup.valid.} =
  ## Presence distinguishes a present-empty value from authenticated absence.
  lookup.found
func root*(lookup: VerifiedStateLookup): StateRoot {.requires: lookup.valid.} =
  ## Preserve complete root identity rather than exposing a partial child commitment.
  lookup.rootIdentity
func key*(lookup: VerifiedStateLookup): StateKey {.requires: lookup.valid.} =
  ## Lookup authority is restricted to the exact requested serialized key.
  lookup.keyIdentity
proc bytes*(lookup: VerifiedStateLookup): seq[byte] {.requires: lookup.valid and lookup.present.} =
  ## Return detached authenticated bytes only for a present value.
  lookup.proof.suppliedValue.value
func bit(key: StateKey, depth: int): bool =
  ## Internal callers prove 0..247 before selecting an MSB-first key bit.
  let bytes = array[31, byte](key)
  (bytes[depth div 8] and byte(128 shr (depth mod 8))) != 0
proc verifyStateProof*(proof: StateProof, expectedRoot: StateRoot, query: StateKey,
    limits: StateProofLimits): StateProofResult[VerifiedStateLookup] =
  ## Check a complete membership path against caller trust; no supplied root travels inside the proof.
  let data = proof.data
  if data == nil:
    return StateProofResult[VerifiedStateLookup](status: StateProofError.Uninitialized)
  if uint64(data.nodes.len) > uint64(limits.nodes) or
      uint64(data.value.len) > uint64(limits.valueBytes):
    return StateProofResult[VerifiedStateLookup](status: StateProofError.LimitExceeded)
  if data.nodes.len == 0:
    # An empty dictionary is the zero identity, not Blake2b(empty), and carries no supplied value.
    if data.value.len != 0:
      return StateProofResult[VerifiedStateLookup](status: StateProofError.InvalidProof)
    if array[32, byte](expectedRoot) != default(array[32, byte]):
      return StateProofResult[VerifiedStateLookup](status: StateProofError.RootMismatch)
    return StateProofResult[VerifiedStateLookup](status: StateProofError.None,
      completed: VerifiedStateLookup(proof: proof, rootIdentity: expectedRoot,
        keyIdentity: query, found: false))
  var expected = array[32, byte](expectedRoot)
  var partial = false
  for depth, node in data.nodes:
    # Authenticate root or selected edge without fabricating a left child's discarded high bit.
    let hashed = hashStateNode(node)
    if hashed.error != StateLayoutError.None:
      return StateProofResult[VerifiedStateLookup](status: StateProofError.BackendFailure)
    var actual = array[32, byte](hashed.value)
    if partial:
      actual[0] = actual[0] and 127 # Left comparison uses exactly its committed 255 bits.
    if actual != expected:
      return StateProofResult[VerifiedStateLookup](status: StateProofError.RootMismatch)
    let info = decodeStateNode(array[64, byte](node)).value.node
    case info.kind
    of StateNodeKind.Branch:
      # Captured paths have at most 248 branches before a leaf or an empty selected edge.
      if query.bit(depth):
        expected = array[32, byte](info.right)
        partial = false
      else:
        expected = array[32, byte](info.left)
        partial = true
      if depth == data.nodes.len - 1:
        # A short path is absence only at the authenticated zero selected edge.
        if expected != default(array[32, byte]) or data.value.len != 0:
          return StateProofResult[VerifiedStateLookup](status: StateProofError.InvalidProof)
        return StateProofResult[VerifiedStateLookup](status: StateProofError.None,
          completed: VerifiedStateLookup(proof: proof, rootIdentity: expectedRoot,
            keyIdentity: query, found: false))
    of StateNodeKind.EmbeddedLeaf, StateNodeKind.HashedLeaf:
      # Structural capture guarantees this is the terminal; require exact key and value preimage.
      let leafKey = if info.kind == StateNodeKind.EmbeddedLeaf: info.embeddedKey else: info.hashedKey
      for prefix in 0..<depth:
        # A different leaf proves absence only in the selected subtree, never across another branch.
        if leafKey.bit(prefix) != query.bit(prefix):
          return StateProofResult[VerifiedStateLookup](status: StateProofError.KeyMismatch)
      if array[31, byte](leafKey) != array[31, byte](query):
        if data.value.len != 0:
          return StateProofResult[VerifiedStateLookup](status: StateProofError.InvalidProof)
        return StateProofResult[VerifiedStateLookup](status: StateProofError.None,
          completed: VerifiedStateLookup(proof: proof, rootIdentity: expectedRoot,
            keyIdentity: query, found: false))
      let encoded = encodeStateLeaf(query, data.value, limits.valueBytes)
      if encoded.error != StateLayoutError.None:
        return StateProofResult[VerifiedStateLookup](status: StateProofError.BackendFailure)
      if array[64, byte](encoded.value) != array[64, byte](node):
        return StateProofResult[VerifiedStateLookup](status: StateProofError.MissingValue)
  StateProofResult[VerifiedStateLookup](status: StateProofError.None,
    completed: VerifiedStateLookup(proof: proof, rootIdentity: expectedRoot,
      keyIdentity: query, found: true))
