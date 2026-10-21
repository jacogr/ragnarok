# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded immutable path witnesses for the pinned state trie. Capture validates structure only;
## independently supplied roots and keys grant lookup authority through a separate verifier.
import std/algorithm
import ../codec/[bounded, state_layout, state_trie]

type
  StateProofLimits* = object ## Independent ceilings apply before path/value copying or hashing.
    nodes*: ElementLimit
    valueBytes*: ByteLimit
  StateProofError* {.pure.} = enum ## Failure alternatives never expose a proof prefix or lookup payload.
    Uninitialized, None, LimitExceeded, InvalidProof, InvalidIndex, RootMismatch,
    KeyMismatch, BackendFailure, MissingValue, StoreFailure, Truncated, NonCanonical, DuplicateKey, LengthOverflow
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

type
  ProofKey = object ## Fixed private identities retain only indices into synchronously borrowed entries.
    key: StateKey
    index: int
func compare(left, right: ProofKey): int =
  ## Lexicographic key order agrees with MSB-first trie partitions.
  let a = array[31, byte](left.key)
  let b = array[31, byte](right.key)
  for i in 0..<31:
    # Stop at the first differing byte; no payload data participates in ordering.
    if a[i] < b[i]: return -1
    if a[i] > b[i]: return 1
  0
func partition(keys: seq[ProofKey], first, stop, depth: int): int =
  ## Locate the first one bit in a sorted range sharing all preceding bits.
  var low = first
  var high = stop
  while low < high:
    # Subtraction bounds midpoint arithmetic within the existing range.
    let middle = low + (high-low) div 2
    if keys[middle].key.bit(depth): high = middle
    else: low = middle + 1
  low
proc planProof(keys: seq[ProofKey], first, stop, depth: int, selected: bool,
    query: StateKey, limits: StateTrieLimits, proofLimits: StateProofLimits,
    used: var uint64, pathNodes: var int, valueIndex: var int): StateProofError =
  ## Count the complete topology and selected path before any cryptographic call.
  if first == stop: return StateProofError.None
  if used >= uint64(limits.nodes): return StateProofError.LimitExceeded
  inc used
  if selected:
    # At most 249 fixed nodes may be retained, independent of complete-map topology.
    if uint64(pathNodes) >= uint64(proofLimits.nodes): return StateProofError.LimitExceeded
    inc pathNodes
  if stop-first == 1:
    # Only an exact key match authorizes retaining the source value.
    if selected and array[31, byte](keys[first].key) == array[31, byte](query):
      valueIndex = keys[first].index
    return StateProofError.None
  if depth >= 248: return StateProofError.DuplicateKey
  let middle = partition(keys, first, stop, depth)
  let right = query.bit(depth)
  let leftError = planProof(keys, first, middle, depth+1, selected and not right,
    query, limits, proofLimits, used, pathNodes, valueIndex)
  if leftError != StateProofError.None: return leftError
  planProof(keys, middle, stop, depth+1, selected and right,
    query, limits, proofLimits, used, pathNodes, valueIndex)
proc buildProof(entries: openArray[StateEntry], keys: seq[ProofKey], first, stop,
    depth: int, selected: bool, query: StateKey, perValue: ByteLimit,
    path: var seq[EncodedStateNode]): StateProofResult[StateNodeHash] =
  ## Commit each complete-map node once while retaining only the queried path.
  if first == stop:
    return StateProofResult[StateNodeHash](status: StateProofError.None,
      completed: default(StateNodeHash))
  let position = path.len
  if selected:
    path.add(default(EncodedStateNode)) # Reserve parent-before-child order without moving ancestors.
  var encoded = default(EncodedStateNode)
  if stop-first == 1:
    # Use the canonical shared leaf encoder; no independently invented node framing.
    let leaf = encodeStateLeaf(keys[first].key, entries[keys[first].index].value, perValue)
    if leaf.error != StateLayoutError.None:
      return StateProofResult[StateNodeHash](status: StateProofError.BackendFailure)
    encoded = leaf.value
  else:
    # Each branch preserves unary topology and the exact pinned left commitment truncation.
    let middle = partition(keys, first, stop, depth)
    let rightSide = query.bit(depth)
    let left = buildProof(entries, keys, first, middle, depth+1,
      selected and not rightSide, query, perValue, path)
    if left.error != StateProofError.None: return left
    let right = buildProof(entries, keys, middle, stop, depth+1,
      selected and rightSide, query, perValue, path)
    if right.error != StateProofError.None: return right
    encoded = encodeStateBranch(left.value, right.value)
  if selected:
    path[position] = encoded # Publish into private scratch only after both children complete.
  let hashed = hashStateNode(encoded)
  if hashed.error != StateLayoutError.None:
    return StateProofResult[StateNodeHash](status: StateProofError.BackendFailure)
  StateProofResult[StateNodeHash](status: StateProofError.None, completed: hashed.value)
proc prepareProofKeys(entries: openArray[StateEntry], mapLimits: StateTrieLimits): StateProofResult[
    seq[ProofKey]] =
  ## Share complete-map preflight without copying values or performing cryptographic work.

  if uint64(entries.len) > uint64(mapLimits.items):
    return StateProofResult[seq[ProofKey]](status: StateProofError.LimitExceeded)
  if entries.len > high(int) div sizeof(ProofKey):
    return StateProofResult[seq[ProofKey]](status: StateProofError.LengthOverflow)
  var total = 0'u64
  for entry in entries:
    # Aggregate subtraction is safe because each preceding successful addition stayed within policy.
    let size = uint64(entry.value.len)
    if size > uint64(mapLimits.perValue) or size > uint64(mapLimits.totalValueBytes)-total:
      return StateProofResult[seq[ProofKey]](status: StateProofError.LimitExceeded)
    total += size
  var keys = newSeq[ProofKey](entries.len)
  for i, entry in entries:
    keys[i] = ProofKey(key: entry.key, index: i) # Caller order and values remain untouched.
  keys.sort(compare)
  for i in 1..<keys.len:
    # Equal and unequal duplicate values are equally invalid mapping inputs.
    if compare(keys[i-1], keys[i]) == 0:
      return StateProofResult[seq[ProofKey]](status: StateProofError.DuplicateKey)
  StateProofResult[seq[ProofKey]](status: StateProofError.None, completed: keys)
proc generateStateProof*(entries: openArray[StateEntry], query: StateKey,
    mapLimits: StateTrieLimits, limits: StateProofLimits): StateProofResult[StateProof] =
  ## Generate from one complete borrowed map; quotas and duplicate keys refuse before hashing.
  let prepared = prepareProofKeys(entries, mapLimits)
  if prepared.error != StateProofError.None:
    return StateProofResult[StateProof](status: prepared.error)
  let keys = prepared.value
  var used = 0'u64
  var pathNodes = 0
  var valueIndex = -1
  let planned = planProof(keys, 0, keys.len, 0, true, query,
    mapLimits, limits, used, pathNodes, valueIndex)
  if planned != StateProofError.None:
    return StateProofResult[StateProof](status: planned)
  if valueIndex >= 0 and uint64(entries[valueIndex].value.len) > uint64(limits.valueBytes):
    return StateProofResult[StateProof](status: StateProofError.LimitExceeded)
  var path: seq[EncodedStateNode] = @[]
  let built = buildProof(entries, keys, 0, keys.len, 0, true, query, mapLimits.perValue, path)
  if built.error != StateProofError.None:
    return StateProofResult[StateProof](status: built.error)
  if valueIndex >= 0:
    return captureStateProof(path, entries[valueIndex].value, limits)
  captureStateProof(path, [], limits) # Absence never copies the neighboring value.

func proofFailure*[T](reason: StateProofError): StateProofResult[T] {.requires:
    reason != StateProofError.None.} =
  ## Integration adapters may preserve failure reasons but cannot fabricate successful proof authority.
  StateProofResult[T](status: reason)

type
  StateProofQuery* = object ## Caller-owned unverified witness and exact requested key; root authority remains separate.
    key*: StateKey
    proof*: StateProof
  StateProofBatchLimits* = object ## Whole-batch ceilings supplement each individual witness policy.
    items*, nodes*: ElementLimit
    valueBytes*: ByteLimit
  VerifiedBatchData = ref object ## Ordered immutable results retain only successful verified evidence.
    lookups: seq[VerifiedStateLookup]
  VerifiedStateProofBatch* = object ## Publication is all-or-neither, including duplicate requested keys.
    data: nil VerifiedBatchData
func len*(batch: VerifiedStateProofBatch): int =
  ## Defaults have no results; an explicit successful empty batch is independently initialized.
  let data = batch.data
  if data == nil: 0 else: data.lookups.len
func valid*(batch: VerifiedStateProofBatch): bool =
  ## Distinguish a valid empty batch from an uninitialized owner.
  batch.data != nil
proc lookupAt*(batch: VerifiedStateProofBatch, index: int): StateProofResult[VerifiedStateLookup] =
  ## An ordinal is interpreted only against its exact retained batch owner.
  let data = batch.data
  if data == nil:
    return proofFailure[VerifiedStateLookup](StateProofError.Uninitialized)
  if index < 0 or index >= data.lookups.len:
    return proofFailure[VerifiedStateLookup](StateProofError.InvalidIndex)
  StateProofResult[VerifiedStateLookup](status: StateProofError.None, completed: data.lookups[index])
proc verifyStateProofs*(queries: openArray[StateProofQuery], expectedRoot: StateRoot,
    limits: StateProofLimits, aggregate: StateProofBatchLimits): StateProofResult[
        VerifiedStateProofBatch] =
  ## Preflight every owner and both aggregate sums before authenticating the first query.
  if uint64(queries.len) > uint64(aggregate.items):
    return proofFailure[VerifiedStateProofBatch](StateProofError.LimitExceeded)
  if queries.len > high(int) div sizeof(VerifiedStateLookup):
    return proofFailure[VerifiedStateProofBatch](StateProofError.LengthOverflow)
  var nodes = 0'u64
  var bytes = 0'u64
  for query in queries:
    # Duplicates preserve request order and consume their full independent resource allowance.
    let data = query.proof.data
    if data == nil:
      return proofFailure[VerifiedStateProofBatch](StateProofError.Uninitialized)
    let count = uint64(data.nodes.len)
    let size = uint64(data.value.len)
    if count > uint64(limits.nodes) or size > uint64(limits.valueBytes) or
        count > uint64(aggregate.nodes)-nodes or size > uint64(aggregate.valueBytes)-bytes:
      return proofFailure[VerifiedStateProofBatch](StateProofError.LimitExceeded)
    nodes += count
    bytes += size
  var completed = newSeq[VerifiedStateLookup](queries.len)
  for i, query in queries:
    # A later cryptographic failure discards all earlier private successful results.
    let checked = verifyStateProof(query.proof, expectedRoot, query.key, limits)
    if checked.error != StateProofError.None:
      return proofFailure[VerifiedStateProofBatch](checked.error)
    completed[i] = checked.value
  StateProofResult[VerifiedStateProofBatch](status: StateProofError.None,
    completed: VerifiedStateProofBatch(data: VerifiedBatchData(lookups: completed)))

type
  ProofSetData = ref object ## Immutable ordered unverified witnesses, distinct from a verified batch.
    queries: seq[StateProofQuery]
  StateProofSet* = object ## Generated paths preserve repeated keys and independent proof ownership.
    data: nil ProofSetData
func valid*(proofs: StateProofSet): bool =
  ## An explicit empty set differs from a default owner.
  proofs.data != nil
func len*(proofs: StateProofSet): int =
  ## Defaults expose no entries.
  let data = proofs.data
  if data == nil: 0 else: data.queries.len
proc queryAt*(proofs: StateProofSet, index: int): StateProofResult[StateProofQuery] =
  ## Return one copied query bound to the selected generated set ordinal.
  let data = proofs.data
  if data == nil: return proofFailure[StateProofQuery](StateProofError.Uninitialized)
  if index < 0 or index >= data.queries.len:
    return proofFailure[StateProofQuery](StateProofError.InvalidIndex)
  StateProofResult[StateProofQuery](status: StateProofError.None, completed: data.queries[index])
proc generateStateProofs*(entries: openArray[StateEntry], queries: openArray[StateKey],
    mapLimits: StateTrieLimits, limits: StateProofLimits,
    aggregate: StateProofBatchLimits): StateProofResult[StateProofSet] =
  ## Plan every selected path and aggregate ceiling before committing any map node.
  if uint64(queries.len) > uint64(aggregate.items):
    return proofFailure[StateProofSet](StateProofError.LimitExceeded)
  if queries.len > high(int) div sizeof(StateProofQuery):
    return proofFailure[StateProofSet](StateProofError.LengthOverflow)
  let prepared = prepareProofKeys(entries, mapLimits)
  if prepared.error != StateProofError.None:
    return proofFailure[StateProofSet](prepared.error)
  let keys = prepared.value
  var indices = newSeq[int](queries.len)
  var nodes = 0'u64
  var bytes = 0'u64
  for i, query in queries:
    # Full topology is bounded for each query; no query can borrow another query's individual ceiling.
    var used = 0'u64
    var count = 0
    var valueIndex = -1
    let planned = planProof(keys, 0, keys.len, 0, true, query,
      mapLimits, limits, used, count, valueIndex)
    if planned != StateProofError.None: return proofFailure[StateProofSet](planned)
    let size = if valueIndex < 0: 0'u64 else: uint64(entries[valueIndex].value.len)
    if size > uint64(limits.valueBytes) or uint64(count) > uint64(aggregate.nodes)-nodes or
        size > uint64(aggregate.valueBytes)-bytes:
      return proofFailure[StateProofSet](StateProofError.LimitExceeded)
    nodes += uint64(count)
    bytes += size
    indices[i] = valueIndex
  var completed = newSeq[StateProofQuery](queries.len)
  for i, query in queries:
    # Each query commits the bounded map independently; sorted key scratch is reused, not rehashed prefixes.
    var path: seq[EncodedStateNode] = @[]
    let built = buildProof(entries, keys, 0, keys.len, 0, true, query, mapLimits.perValue, path)
    if built.error != StateProofError.None: return proofFailure[StateProofSet](built.error)
    let captured = if indices[i] < 0: captureStateProof(path, [], limits)
      else: captureStateProof(path, entries[indices[i]].value, limits)
    if captured.error != StateProofError.None: return proofFailure[StateProofSet](captured.error)
    completed[i] = StateProofQuery(key: query, proof: captured.value)
  StateProofResult[StateProofSet](status: StateProofError.None,
    completed: StateProofSet(data: ProofSetData(queries: completed)))

proc encodeStateProof*(proof: StateProof, limits: StateProofLimits,
    wireBytes: ByteLimit): StateProofResult[seq[byte]] =
  ## Emit local RSP1 framing; this is not a JAMNP-S message and contains no trusted root or query.
  let data = proof.data
  if data == nil: return proofFailure[seq[byte]](StateProofError.Uninitialized)
  if uint64(data.nodes.len) > uint64(limits.nodes) or
      uint64(data.value.len) > uint64(limits.valueBytes):
    return proofFailure[seq[byte]](StateProofError.LimitExceeded)
  if uint64(data.value.len) > uint64(high(uint32)):
    return proofFailure[seq[byte]](StateProofError.LengthOverflow)
  let overhead = 10'u64 + uint64(data.nodes.len)*64'u64
  if overhead > uint64(wireBytes) or uint64(data.value.len) > uint64(wireBytes)-overhead:
    return proofFailure[seq[byte]](StateProofError.LimitExceeded)
  if uint64(data.value.len) > uint64(high(int))-overhead:
    return proofFailure[seq[byte]](StateProofError.LengthOverflow)
  var output = newSeq[byte](int(overhead)+data.value.len)
  output[0] = byte('R')
  output[1] = byte('S')
  output[2] = byte('P')
  output[3] = byte('1')
  for i in 0..<2:
    output[4+i] = byte((uint64(data.nodes.len) shr (8*i)) and 255) # Canonical fixed E2 node count.
  for i in 0..<4:
    output[6+i] = byte((uint64(data.value.len) shr (8*i)) and 255) # Canonical fixed E4 value length.
  for i, node in data.nodes:
    # Nodes keep exact pinned 64-byte encodings; local framing never rewrites left commitments.
    let bytes = array[64, byte](node)
    for j in 0..<64: output[10+i*64+j] = bytes[j]
  for i, octet in data.value:
    output[int(overhead)+i] = octet # Return new caller-owned storage, not a mutable owner view.
  StateProofResult[seq[byte]](status: StateProofError.None, completed: output)

proc decodeStateProof*(input: openArray[byte], limits: StateProofLimits,
    wireBytes: ByteLimit): StateProofResult[StateProof] =
  ## Decode exactly one bounded local envelope; no alternate version, suffix or partial success is accepted.
  if uint64(input.len) > uint64(wireBytes):
    return proofFailure[StateProof](StateProofError.LimitExceeded)
  if input.len < 10: return proofFailure[StateProof](StateProofError.Truncated)
  if input[0] != byte('R') or input[1] != byte('S') or input[2] != byte('P') or input[3] != byte('1'):
    return proofFailure[StateProof](StateProofError.NonCanonical)
  let count = uint64(input[4]) or (uint64(input[5]) shl 8)
  var size = 0'u64
  for i in 0..<4:
    size = size or (uint64(input[6+i]) shl (8*i)) # Widen before shifting untrusted E4 octets.
  if count > 249 or count > uint64(limits.nodes) or size > uint64(limits.valueBytes):
    return proofFailure[StateProof](StateProofError.LimitExceeded)
  let overhead = 10'u64 + count*64'u64
  let total = overhead+size # Both operands have fixed validated domains far below uint64 overflow.
  if total > uint64(input.len): return proofFailure[StateProof](StateProofError.Truncated)
  if total != uint64(input.len): return proofFailure[StateProof](StateProofError.NonCanonical)
  var nodes = newSeq[EncodedStateNode](int(count))
  for i in 0..<int(count):
    # Every node's full extent was proven before allocation and indexing.
    var bytes = default(array[64, byte])
    for j in 0..<64: bytes[j] = input[10+i*64+j]
    nodes[i] = EncodedStateNode(bytes)
  var supplied = newSeq[byte](int(size))
  for i in 0..<int(size):
    supplied[i] = input[int(overhead)+i] # Retain no caller-owned mutable byte storage.
  captureStateProof(nodes, supplied, limits) # Canonical layout/path checks remain shared and noncryptographic.
