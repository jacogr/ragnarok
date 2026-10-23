# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable complete GP 0.8.0 state tries with path-copying atomic batches and cached hashes.
## Inputs are borrowed for synchronous calls; published nodes and owned values never mutate.
## Exposes complete revisions, retained lookup values, explicit limits and guarded results.

import std/[algorithm, assertions]
import ./[node_records, state_proof]
import ../codec/[state_trie, state_layout, bounded]

type
  FullStateTrieLimits* = object ## Complete-map ceilings plus independent borrowed batch limits.
    trie*: StateTrieLimits
    writes*: ElementLimit
    writeValueBytes*: ByteLimit
  TrieWriteKind* {.pure.} = enum ## One unique mutation per key; Delete must have no payload.
    Put, Delete
  TrieWrite* = object ## Borrowed bytes remain stable until apply returns; Put copies its payload.
    key*: StateKey
    kind*: TrieWriteKind
    value*: seq[byte]
  TrieError* {.pure.} = enum ## Defaults and failures never authorize payload extraction.
    Uninitialized, None, MissingKey, InvalidWrite, LimitExceeded, DuplicateKey,
    LengthOverflow, BackendFailure
  TrieResult*[T] = object ## Private discriminator and payload enforce success-only access.
    case status: TrieError
    of None:
      completed: T
    else:
      discard             # Refusals own their reason alone.
  TrieNode = ref object         ## Acyclic private alternatives own only leaf data or branch children/aggregates.
    digest: StateNodeHash
    hashed: bool                ## Only newly built unpublished nodes may receive cached hashes.
    case leaf: bool
    of true:
      key: StateKey
      payload: seq[byte]        ## Leaf totals derive from one entry/node and this owned length.
    of false:
      left, right: nil TrieNode
      entries: int
      nodes, valueBytes: uint64 ## Only branches need cached aggregate summaries.
  RevisionData = ref object ## A nonnil owner distinguishes an initialized empty trie from a default.
    root: nil TrieNode
    limits: FullStateTrieLimits
  FullStateTrie* = object ## Cheap copies retain one immutable full-map revision and its resource policy.
    data: nil RevisionData
  TrieValue* = object ## A retained leaf survives retirement of all originating revision handles.
    owner: nil TrieNode
  WriteIndex = object ## Sort fixed identities without copying or retaining caller payloads.
    key: StateKey
    position: int

func error*[T](outcome: TrieResult[T]): TrieError =
  ## Inspect a reason without granting access to any completed payload.
  outcome.status

func value*[T](outcome: TrieResult[T]): T {.inline,
    requires: outcome.status == TrieError.None.} =
  ## Extract only a successful revision or retained value under checked optimized builds.
  outcome.completed

proc takeValue*[T](outcome: var TrieResult[T]): T {.inline, requires: outcome.status ==
    TrieError.None.} =
  ## Transfer a successful revision/value/export once without copying; consumed results retain only Uninitialized.
  result = move(outcome.completed)
  outcome = TrieResult[T](status: TrieError.Uninitialized)

func compareKey(left, right: StateKey): int =
  ## Lexicographic byte order agrees with the protocol's MSB-first traversal.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    if a[i] < b[i]: return -1 # First differing octet fixes the order.
    if a[i] > b[i]: return 1 # Later octets cannot change it.
  0

proc compareWrite(left, right: WriteIndex): int =
  ## Compare identities only, leaving the borrowed mutation array unchanged.
  compareKey(left.key, right.key)

func one(key: StateKey, depth: int): bool =
  ## Internal callers prove depth<248 before reading a full serialized key bit.
  let raw = array[31, byte](key)
  (raw[depth div 8] and byte(128 shr (depth mod 8))) != 0

func entryCount(node: nil TrieNode): int =
  ## Empty children contribute zero; a leaf always contributes exactly one complete entry.
  if node == nil: 0
  elif node.leaf: 1
  else: node.entries

func nodeCount(node: nil TrieNode): uint64 =
  ## Leaf topology is exactly one node; only branch totals require a stored aggregate.
  if node == nil: 0'u64
  elif node.leaf: 1'u64
  else: node.nodes

func valueSize(node: nil TrieNode): uint64 =
  ## Leaf bytes derive from the immutable payload; branch caches sum complete descendant values.
  if node == nil: 0'u64
  elif node.leaf: uint64(node.payload.len)
  else: node.valueBytes

proc find(node: nil TrieNode, key: StateKey): nil TrieNode =
  ## Iterative bounded traversal never grants absence based on a partial map.
  var current = node
  var depth = 0
  while current != nil:
    if current.leaf:
      if compareKey(current.key, key) == 0: return current # Full key equality is mandatory.
      return nil # A different singleton proves absence in this complete subtree.
    if one(key, depth): current = current.right # Follow the next committed one-bit edge.
    else: current = current.left # Empty zero-bit children terminate normally.
    inc depth
  nil

proc leaf(key: StateKey, bytes: openArray[byte]): TrieNode =
  ## Copy new caller values after payload preflight; no mutable source backing can escape.
  var owned = newSeq[byte](bytes.len)
  for i, octet in bytes: owned[i] = octet # Empty values remain initialized leaves.
  TrieNode(leaf: true, key: key, payload: owned)

proc branch(left, right: nil TrieNode): nil TrieNode =
  ## Normalize empty/singleton subtrees while preserving protocol-required unary branches.
  if left == nil:
    if right == nil or right.leaf: return right # A singleton is a leaf at every depth.
  if right == nil and left != nil and left.leaf: return left # Collapse the last surviving leaf.
  # Preflight bounds entries by high(int) and uint64/249, and payload totals by uint64.
  # Each copied/merged child is a final subtree; no cached sum includes both versions of one key.
  TrieNode(leaf: false, left: left, right: right, entries: entryCount(left)+entryCount(right),
    nodes: 1+nodeCount(left)+nodeCount(right), valueBytes: valueSize(left)+valueSize(right))

proc writeSplit(ordered: openArray[WriteIndex], first, stop, depth: int): int =
  ## Sorted ranges share previous bits, so binary search finds the first one-bit key at this depth.
  var lower = first
  var upper = stop
  while lower < upper:
    let middle = lower+(upper-lower) div 2 # Difference-based arithmetic stays inside the bounded range.
    if one(ordered[middle].key, depth): upper = middle # The first one-bit key is no later than middle.
    else: lower = middle+1 # This zero-bit key and every earlier slot precede the partition.
  lower

proc buildInitial(ordered: openArray[WriteIndex], writes: openArray[StateEntry],
    first, stop, depth: int): nil TrieNode =
  ## Build each final node once from a sorted unique range sharing the previous key bits.
  if first == stop: return nil # An empty partition has the canonical empty identity.
  if stop-first == 1:
    let write = writes[ordered[first].position]
    return leaf(write.key, write.value) # Singleton leaves need no intervening unary branches.
  assert depth < 248 # Distinct full keys must split before exhausting their serialized bits.
  let split = writeSplit(ordered, first, stop, depth)
  let left = buildInitial(ordered, writes, first, split, depth+1)
  let right = buildInitial(ordered, writes, split, stop, depth+1)
  branch(left, right) # Retain unary branches whenever their nonempty child contains multiple leaves.

proc remove(node: nil TrieNode, key: StateKey, depth: int): nil TrieNode =
  ## Delete by path copying; absent keys reuse their exact previous subtree identities.
  if node == nil: return nil # Absence is an idempotent no-op.
  if node.leaf:
    if compareKey(node.key, key) == 0: return nil # Remove only the full identity.
    return node # A different leaf is unaffected.
  if one(key, depth):
    let changed = remove(node.right, key, depth+1)
    if changed == node.right: return node # No changed descendant means no copied branch.
    return branch(node.left, changed)
  let changed = remove(node.left, key, depth+1)
  if changed == node.left: return node # Share the complete unaffected subtree.
  branch(changed, node.right)

proc insert(node: nil TrieNode, added: TrieNode, depth: int): nil TrieNode =
  ## Copy the affected path, expanding a singleton through every shared-prefix bit.
  if node == nil: return added # Empty subtrees immediately become one leaf.
  if node.leaf:
    if compareKey(node.key, added.key) == 0: return added # A replacement occupies only the final leaf position.
    if one(node.key, depth) == one(added.key, depth):
      let child = insert(node, added, depth+1)
      if one(added.key, depth): return branch(nil, child) # Preserve shared one-bit unary nodes.
      return branch(child, nil) # Preserve shared zero-bit unary nodes.
    if one(added.key, depth): return branch(node, added) # First differing bit separates both leaves.
    return branch(added, node)
  if one(added.key, depth):
    return branch(node.left, insert(node.right, added, depth+1)) # Share the untouched left subtree.
  branch(insert(node.left, added, depth+1), node.right)

proc mergeWrites(node: nil TrieNode, ordered: openArray[WriteIndex],
    writes: openArray[TrieWrite], first, stop, depth: int): nil TrieNode =
  ## Copy the union of affected paths once, sharing every complete subtree without a routed write.
  if first == stop: return node # An untouched subtree retains its exact published owner identity.
  if stop-first == 1:
    let write = writes[ordered[first].position]
    if write.kind == TrieWriteKind.Delete:
      return remove(node, write.key, depth) # Absent deletion propagates the original identity unchanged.
    return insert(node, leaf(write.key, write.value),
        depth) # Replacement never retains both leaf versions in a cached sum.
  assert depth < 248 # Unique routed write keys must partition before the complete key domain ends.
  var left: nil TrieNode = nil
  var right: nil TrieNode = nil
  if node != nil:
    if node.leaf:
      if one(node.key, depth): right = node # Expand a singleton logically, allocating no temporary branch.
      else: left = node
    else:
      left = node.left # Immutable children remain independently retained while both candidates are built.
      right = node.right
  let split = writeSplit(ordered, first, stop, depth)
  let changedLeft = mergeWrites(left, ordered, writes, first, split, depth+1)
  let changedRight = mergeWrites(right, ordered, writes, split, stop, depth+1)
  if node != nil and not node.leaf and changedLeft == left and changedRight == right:
    return node # A multi-key absent-delete batch must preserve revision and shared branch identities.
  branch(changedLeft, changedRight) # Normalize only the final children after all routed deletions/replacements.

proc hashCandidate(node: nil TrieNode, perValue: ByteLimit): TrieError =
  ## Fill private caches bottom-up; shared published nodes are already hashed and never written.
  if node == nil or node.hashed: return TrieError.None # Reuse empty identities and committed subtrees.
  var encoded = default(EncodedStateNode)
  if node.leaf:
    let prepared = encodeStateLeaf(node.key, node.payload, perValue)
    if prepared.error != StateLayoutError.None: return TrieError.BackendFailure # Policy was checked before allocation.
    encoded = prepared.value
  else:
    let left = hashCandidate(node.left, perValue)
    if left != TrieError.None: return left # Never hash a branch after a failed child.
    let right = hashCandidate(node.right, perValue)
    if right != TrieError.None: return right # Discard the private partially hashed graph on refusal.
    let leftNode = node.left
    let rightNode = node.right
    let a = if leftNode == nil: default(StateNodeHash) else: leftNode.digest
    let b = if rightNode == nil: default(StateNodeHash) else: rightNode.digest
    encoded = encodeStateBranch(a, b)
  let committed = hashStateNode(encoded)
  if committed.error != StateLayoutError.None: return TrieError.BackendFailure # No failed digest becomes a zero root.
  node.digest = committed.value
  node.hashed = true
  TrieError.None

func sameTrieRevision*(left, right: FullStateTrie): bool =
  ## Observe initialized revision identity; independently rebuilt equal roots are different owners.
  left.data != nil and left.data == right.data

proc commitment*(trie: FullStateTrie): StateTrieCommitment {.requires: trie.data != nil.} =
  ## Return scalar root/count copies; callers cannot alter cached topology or identities.
  let data = trie.data
  assert data != nil # Bind the contract-checked owner once for nullable analysis.
  let root = data.root
  let digest = if root == nil: default(StateNodeHash) else: root.digest
  StateTrieCommitment(root: StateRoot(array[32, byte](digest)), entries: entryCount(root),
    nodes: nodeCount(root))

proc lookup*(trie: FullStateTrie, key: StateKey): TrieResult[TrieValue] =
  ## Distinguish default revisions, missing keys and present-empty retained values.
  let data = trie.data
  if data == nil: return TrieResult[TrieValue](status: TrieError.Uninitialized)
  let found = find(data.root, key)
  if found == nil: return TrieResult[TrieValue](status: TrieError.MissingKey)
  TrieResult[TrieValue](status: TrieError.None, completed: TrieValue(owner: found))

proc byteLength*(view: TrieValue): int {.requires: view.owner != nil.} =
  ## Read the retained leaf extent, including a present zero-byte value.
  let owner = view.owner
  assert owner != nil # Keep the retained leaf stable through the checked access.
  owner.payload.len

proc bytes*(view: TrieValue): seq[byte] {.requires: view.owner != nil.} =
  ## Copy a value out; mutable backing storage never crosses the public boundary.
  let owner = view.owner
  assert owner != nil # Retain the checked leaf once throughout the copy.
  result = newSeq[byte](owner.payload.len)
  for i in 0..<owner.payload.len: result[i] = owner.payload[i] # Retain the owner throughout copying.

proc applyBatch(source: FullStateTrie, writes: openArray[TrieWrite]): TrieResult[FullStateTrie] =
  ## Preflight the complete batch, build a private topology, then hash and return one new revision.
  ## No operation changes source or any previously retained revision, including backend refusal.
  let data = source.data
  if data == nil: return TrieResult[FullStateTrie](status: TrieError.Uninitialized)
  let limits = data.limits
  if uint64(writes.len) > uint64(limits.writes):
    return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Bound sorting scratch first.
  if writes.len > high(int) div sizeof(WriteIndex):
    return TrieResult[FullStateTrie](status: TrieError.LengthOverflow) # Typed scratch must fit native addressing.
  var writeBytes = 0'u64
  for write in writes:
    if write.kind notin {TrieWriteKind.Put, TrieWriteKind.Delete}:
      return TrieResult[FullStateTrie](status: TrieError.InvalidWrite) # Invalid tags cannot silently delete.
    if write.kind == TrieWriteKind.Delete and write.value.len != 0:
      return TrieResult[FullStateTrie](status: TrieError.InvalidWrite) # Deletes have no payload semantics.
    let size = uint64(write.value.len)
    if size > uint64(limits.trie.perValue) or size > uint64(limits.writeValueBytes)-writeBytes:
      return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Prove running addition before updating it.
    writeBytes += size
  if writes.len == 0:
    return TrieResult[FullStateTrie](status: TrieError.None, completed: source) # No allocation or hashing.
  var ordered = newSeq[WriteIndex](writes.len)
  for i, write in writes: ordered[i] = WriteIndex(key: write.key, position: i) # Only fixed identities are sorted.
  ordered.sort(compareWrite)
  for i in 1..<ordered.len:
    if compareKey(ordered[i-1].key, ordered[i].key) == 0:
      return TrieResult[FullStateTrie](status: TrieError.DuplicateKey) # Reject even identical mutations.
  var count = entryCount(data.root)
  var total = valueSize(data.root)
  for index in ordered:
    let old = find(data.root, index.key)
    if old != nil:
      dec count # Account for every overwritten/deleted leaf before counting any new value.
      total -= valueSize(old)
  for index in ordered:
    let write = writes[index.position]
    if write.kind == TrieWriteKind.Put:
      if uint64(count) >= uint64(limits.trie.items) or count >= high(int) div sizeof(StateEntry):
        return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Final map count and typed input extent are bounded.
      if uint64(count) >= high(uint64) div 249:
        return TrieResult[FullStateTrie](status: TrieError.LengthOverflow) # At most 249 nodes per entry proves cached node additions.
      let size = uint64(write.value.len)
      if size > uint64(limits.trie.totalValueBytes)-total:
        return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Deleted bytes release budget before insertion.
      inc count
      total += size
  let candidate = mergeWrites(data.root, ordered, writes, 0, ordered.len, 0)
  if nodeCount(candidate) > uint64(limits.trie.nodes):
    return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Exact final topology refuses before any hashing.
  let hashed = hashCandidate(candidate, limits.trie.perValue)
  if hashed != TrieError.None: return TrieResult[FullStateTrie](
      status: hashed) # Partial caches belong only to discarded new nodes.
  if candidate == data.root:
    return TrieResult[FullStateTrie](status: TrieError.None,
        completed: source) # Absent deletes preserve revision identity.
  TrieResult[FullStateTrie](status: TrieError.None,
    completed: FullStateTrie(data: RevisionData(root: candidate, limits: limits)))

proc apply*(source: FullStateTrie, writes: openArray[TrieWrite]): TrieResult[FullStateTrie] =
  ## Atomically path-copy validated writes, preserving all previous revisions even on hash refusal.
  applyBatch(source, writes)

proc newFullStateTrie*(entries: openArray[StateEntry],
    limits: FullStateTrieLimits): TrieResult[FullStateTrie] =
  ## Build an owned complete revision without routing initial entries through mutation-batch ceilings.
  if uint64(entries.len) > uint64(limits.trie.items):
    return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Bound borrowed entry-derived scratch before allocation.
  if entries.len > high(int) div sizeof(TrieWrite) or entries.len > high(int) div sizeof(StateEntry):
    return TrieResult[FullStateTrie](status: TrieError.LengthOverflow) # Initial typed scratch must fit host addressing.
  if entries.len > high(int) div sizeof(WriteIndex):
    return TrieResult[FullStateTrie](status: TrieError.LengthOverflow) # Bound exact sorting scratch before allocation.
  var total = 0'u64
  for entry in entries:
    let size = uint64(entry.value.len)
    if size > uint64(limits.trie.perValue) or size > uint64(limits.trie.totalValueBytes)-total:
      return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Validate all borrowed bytes before sorting or copying.
    total += size
  var ordered = newSeq[WriteIndex](entries.len)
  for index, entry in entries:
    ordered[index] = WriteIndex(key: entry.key, position: index) # Copy only fixed keys and source positions.
  ordered.sort(compareWrite)
  for index in 1..<ordered.len:
    if compareKey(ordered[index-1].key, ordered[index].key) == 0:
      return TrieResult[FullStateTrie](status: TrieError.DuplicateKey) # Payload quota errors retain precedence over duplicates.
  if entries.len > high(int) div sizeof(StateEntry):
    return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Preserve the final-map extent contract.
  if uint64(entries.len) > high(uint64) div 249:
    return TrieResult[FullStateTrie](status: TrieError.LengthOverflow) # Bound every cached topology addition before building.
  let candidate = buildInitial(ordered, entries, 0, ordered.len, 0)
  if nodeCount(candidate) > uint64(limits.trie.nodes):
    return TrieResult[FullStateTrie](status: TrieError.LimitExceeded) # Exact topology refuses before any cryptographic operation.
  let hashed = hashCandidate(candidate, limits.trie.perValue)
  if hashed != TrieError.None:
    return TrieResult[FullStateTrie](status: hashed) # Failed unpublished nodes retire with their private copied payloads.
  TrieResult[FullStateTrie](status: TrieError.None,
    completed: FullStateTrie(data: RevisionData(root: candidate, limits: limits)))


proc prove*(trie: FullStateTrie, key: StateKey,
    limits: StateProofLimits): TrieResult[StateProof] =
  ## Copy one bounded canonical root-to-terminal path from an immutable complete revision.
  ## Output grants no root trust; verification still requires the independently trusted complete root.
  let data = trie.data
  if data == nil: return TrieResult[StateProof](status: TrieError.Uninitialized) # Defaults cannot prove an empty mapping.
  var current = data.root
  var count = 0
  # Walk the immutable selected path before allocating output or hashing a terminal long value.
  while current != nil:
    if count >= 249 or uint64(count) >= uint64(limits.nodes):
      return TrieResult[StateProof](status: TrieError.LimitExceeded) # Tight caller budgets cannot expose partial paths.
    inc count
    if current.leaf:
      if compareKey(current.key, key) == 0 and uint64(current.payload.len) > uint64(
          limits.valueBytes):
        return TrieResult[StateProof](status: TrieError.LimitExceeded) # Only present raw bytes consume the output-value ceiling.
      break # A matching or different-key singleton is terminal evidence.
    assert count <= 248 # Complete private graphs have at most 248 branch levels.
    current = if one(key, count-1): current.right else: current.left
  var nodes = newSeq[EncodedStateNode](count)
  var payload: seq[byte] = @[]
  current = data.root
  var next = 0
  # The retained immutable owner keeps both walks identical, including selected empty children.
  while current != nil:
    assert next < nodes.len # The first walk proved this exact descriptor extent.
    if current.leaf:
      let encoded = encodeStateLeaf(current.key, current.payload, data.limits.trie.perValue)
      if encoded.error != StateLayoutError.None:
        return TrieResult[StateProof](status: TrieError.BackendFailure) # Long-value hash refusal retires the private partial output.
      nodes[next] = encoded.value
      inc next
      if compareKey(current.key, key) == 0:
        payload = newSeq[byte](current.payload.len)
        for index in 0..<current.payload.len: payload[index] = current.payload[
            index] # Detached bytes never share mutable backing with a leaf.
      break # Absence leaves intentionally omit their raw value, including long values.
    let left = current.left
    let right = current.right
    nodes[next] = encodeStateBranch(
      (if left == nil: default(StateNodeHash) else: left.digest),
      (if right == nil: default(StateNodeHash) else: right.digest))
    inc next
    assert next <= 248 # Bound the next MSB-first key-bit lookup before access.
    current = if one(key, next-1): right else: left
  assert next == nodes.len # Empty roots/children and terminal leaves fill the complete bounded path exactly.
  TrieResult[StateProof](status: TrieError.None, completed: StateProof(nodes: nodes,
      value: payload))

proc omitted(node, base: nil TrieNode): bool =
  ## Equal complete commitments reuse an existing physical subtree; leaves may move after collapse.
  if node == nil: return true # Empty children need no physical record.
  if base == nil: return false # A nonempty subtree needs materialization against an empty base.
  if array[32, byte](node.digest) == array[32, byte](base.digest): return true
  if node.leaf:
    let previous = find(base, node.key)
    return previous != nil and array[32, byte](previous.digest) == array[32, byte](node.digest)
  false

proc baseChild(base: nil TrieNode, depth: int, right: bool): nil TrieNode =
  ## Align immutable base subtrees with the candidate path, including singleton expansion.
  if base == nil: return nil # No base record can be reused on this path.
  if base.leaf:
    if one(base.key, depth) == right: return base # The singleton occupies exactly one side.
    return nil
  if right: base.right else: base.left

proc exportSize(node, base: nil TrieNode, depth: int, limits: TrieExportLimits,
    count, bytes: var uint64): TrieError =
  ## Preflight detached record/value extents without allocating or hashing any node.
  if omitted(node, base): return TrieError.None
  assert node != nil # Omitted empty nodes returned before this bound access.
  if count >= uint64(limits.records) or count >= uint64(high(int) div sizeof(TrieRecord)):
    return TrieError.LimitExceeded # Check descriptor count before increment or later allocation.
  inc count
  if node.leaf:
    if uint64(node.payload.len) > uint64(limits.valueBytes)-bytes:
      return TrieError.LimitExceeded # Aggregate payload subtraction prevents wrapping.
    bytes += uint64(node.payload.len)
  else:
    let left = exportSize(node.left, baseChild(base, depth, false), depth+1, limits, count, bytes)
    if left != TrieError.None: return left # A refused child cannot expose a partial export.
    return exportSize(node.right, baseChild(base, depth, true), depth+1, limits, count, bytes)
  TrieError.None

proc exportNodes(node, base: nil TrieNode, depth: int, output: var seq[TrieRecord], next: var int) =
  ## Emit children before parents, deep-copying values and retaining no canonical graph aliases.
  if not omitted(node, base):
    assert node != nil # Preflight and omission establish a complete physical node.
    if node.leaf:
      var copied = newSeq[byte](node.payload.len)
      for i in 0..<node.payload.len: copied[i] = node.payload[i] # Published backing never escapes.
      output[next] = TrieRecord(kind: TrieRecordKind.Leaf, digest: node.digest,
        key: node.key, payload: copied)
      inc next
    else:
      exportNodes(node.left, baseChild(base, depth, false), depth+1, output, next)
      exportNodes(node.right, baseChild(base, depth, true), depth+1, output, next)
      let left = node.left
      let right = node.right
      output[next] = TrieRecord(kind: TrieRecordKind.Branch, digest: node.digest,
        left: (if left == nil: default(StateNodeHash) else: left.digest),
        right: (if right == nil: default(StateNodeHash) else: right.digest))
      inc next

proc exportTrieChanges*(base, target: FullStateTrie,
    limits: TrieExportLimits): TrieResult[TrieExport] =
  ## Detach only records missing from an explicit complete base; neither root grants chain authority.
  let prior = base.data
  let selected = target.data
  if prior == nil or selected == nil:
    return TrieResult[TrieExport](status: TrieError.Uninitialized) # Defaults cannot describe a complete base/target.
  var count = 0'u64
  var bytes = 0'u64
  let checked = exportSize(selected.root, prior.root, 0, limits, count, bytes)
  if checked != TrieError.None: return TrieResult[TrieExport](status: checked)
  var records = newSeq[TrieRecord](int(count))
  var next = 0
  exportNodes(selected.root, prior.root, 0, records, next) # Preflight proves every exact slot before allocation.
  assert next == records.len # Child-before-parent emission must fill the complete bounded descriptor extent.
  let metadata = target.commitment
  TrieResult[TrieExport](status: TrieError.None, completed: TrieExport(base: base.commitment.root,
    root: metadata.root, entries: uint64(metadata.entries), nodes: metadata.nodes,
        records: records))

proc exportFullTrie*(target: FullStateTrie, limits: TrieExportLimits): TrieResult[TrieExport] =
  ## Materialize a standalone physical revision against the empty complete-map root.
  let empty = newFullStateTrie([], default(FullStateTrieLimits)).value
  exportTrieChanges(empty, target, limits)
