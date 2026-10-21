# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic in-memory physical-node repository verifies complete graphs before publishing revisions.
## Retained immutable read views are independent of later publication and explicit owner close.

import std/[algorithm, assertions]
import ./[node_records, record_codec, full_state_trie, durability]
import ../codec/[state_layout, state_trie, bounded]

type
  RepositoryLimits* = object ## Bound accumulated physical records separately from one complete target.
    codec*: RecordLimits
    records*: ElementLimit
    valueBytes*: ByteLimit
  RepositoryGeneration* = distinct uint64 ## Local publication sequence, unrelated to protocol timeslots.
  RepositoryError* {.pure.} = enum ## Errors expose no partial graph, candidate or publication receipt.
    Uninitialized, None, MissingNode, LimitExceeded, StaleView, BaseMismatch,
    InvalidRecords, InvalidGraph, RecordConflict, GenerationExhausted, RootMismatch, TrieFailure
  RepositoryResult*[T] = object ## Only the selected alternatives own a payload or codec diagnostic.
    case status: RepositoryError
    of None: completed: T
    of InvalidRecords: recordReason: RecordError
    of TrieFailure: trieReason: TrieError
    else: discard               # Default and ordinary refusals retain no graph owner.
  RepositoryData = ref object ## Published immutable node table retains no previous revision owner.
    records: seq[TrieRecord]
    commitment: StateTrieCommitment
    generation: RepositoryGeneration
    valueBytes: uint64
    limits: RepositoryLimits
  RepositoryView* = object ## Owner-bound immutable physical read view with copied scalar metadata.
    data: nil RepositoryData
  NodeRepository* = object ## Copies are independent updateable handles sharing immutable prior data only.
    head: nil RepositoryData
  GraphCounts = object ## Explicitly initialized running totals bound untrusted graph traversal.
    entries, nodes, bytes: uint64

func error*[T](outcome: RepositoryResult[T]): RepositoryError =
  ## Observe only the selected reason.
  outcome.status
func value*[T](outcome: RepositoryResult[T]): T {.inline,
    requires: outcome.status == RepositoryError.None.} =
  ## Extract only a successful complete operation.
  outcome.completed
func recordError*[T](outcome: RepositoryResult[T]): RecordError {.requires:
    outcome.status == RepositoryError.InvalidRecords.} =
  ## Inspect only a selected physical-record integrity refusal.
  outcome.recordReason
func trieError*[T](outcome: RepositoryResult[T]): TrieError {.requires:
    outcome.status == RepositoryError.TrieFailure.} =
  ## Inspect only a selected failed standalone trie reconstruction.
  outcome.trieReason
func compareHash(left, right: StateNodeHash): int =
  ## Full physical addresses use fixed lexical order.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  for i in 0..<32:
    if a[i] < b[i]: return -1 # First different byte fixes address order.
    if a[i] > b[i]: return 1
  0
proc compareRecord(left, right: TrieRecord): int =
  ## Sort records without comparing or copying raw payloads in the comparator.
  compareHash(left.digest, right.digest)
func sameRecord(left, right: TrieRecord): bool =
  ## A digest collision must not silently replace different physical navigation or values.
  left.kind == right.kind and compareHash(left.digest, right.digest) == 0 and
    array[31, byte](left.key) == array[31, byte](right.key) and left.payload == right.payload and
    compareHash(left.left, right.left) == 0 and compareHash(left.right, right.right) == 0
proc copyRecord(source: TrieRecord): TrieRecord =
  ## Deep-copy only mutable byte storage; fixed addresses and keys copy by value.
  var bytes = newSeq[byte](source.payload.len)
  for i, octet in source.payload: bytes[i] = octet
  TrieRecord(kind: source.kind, digest: source.digest, key: source.key, payload: bytes,
    left: source.left, right: source.right)
proc position(records: seq[TrieRecord], digest: StateNodeHash): int =
  ## Binary search uses subtraction-based midpoints and full address equality.
  var first = 0
  var stop = records.len
  while first < stop:
    let middle = first+(stop-first) div 2
    let order = compareHash(records[middle].digest, digest)
    if order < 0: first = middle+1 # Search only larger remaining addresses.
    elif order > 0: stop = middle # Search only smaller remaining addresses.
    else: return middle
  -1
proc graph(records: seq[TrieRecord], digest: StateNodeHash, depth: int,
    prefix: array[31, byte], limits: StateTrieLimits, seen: var seq[bool],
    counts: var GraphCounts): RepositoryError =
  ## Verify complete reachability, bounded acyclic topology and every full key's MSB route.
  if array[32, byte](digest) == default(array[32, byte]): return RepositoryError.None
  let index = position(records, digest)
  if index < 0: return RepositoryError.MissingNode # Partial graphs never become complete revisions.
  if seen[index]: return RepositoryError.InvalidGraph # Cycles and repeated logical subtrees cannot represent a full-key map.
  if counts.nodes >= uint64(limits.nodes): return RepositoryError.LimitExceeded
  inc counts.nodes
  seen[index] = true
  let record = records[index]
  if record.kind == TrieRecordKind.Leaf:
    let key = array[31, byte](record.key)
    for bit in 0..<depth:
      let mask = byte(128 shr (bit mod 8))
      if (key[bit div 8] and mask) != (prefix[bit div 8] and mask):
        return RepositoryError.InvalidGraph # A locally valid node at the wrong path is not a valid trie.
    let size = uint64(record.payload.len)
    if counts.entries >= uint64(limits.items) or size > uint64(limits.perValue) or
        size > uint64(limits.totalValueBytes)-counts.bytes:
      return RepositoryError.LimitExceeded
    inc counts.entries
    counts.bytes += uint64(record.payload.len)
  else:
    if depth >= 248: return RepositoryError.InvalidGraph # No branch may read past the full serialized key domain.
    let before = counts.entries
    let left = graph(records, record.left, depth+1, prefix, limits, seen, counts)
    if left != RepositoryError.None: return left
    var rightPrefix = prefix
    rightPrefix[depth div 8] = rightPrefix[depth div 8] or byte(128 shr (depth mod 8))
    let right = graph(records, record.right, depth+1, rightPrefix, limits, seen, counts)
    if right != RepositoryError.None: return right
    if counts.entries-before < 2: return RepositoryError.InvalidGraph # Singletons must collapse instead of retaining unary paths.
  RepositoryError.None

proc newNodeRepository*(limits: RepositoryLimits): NodeRepository =
  ## Open an initialized empty in-memory owner; allocation exhaustion keeps the fail-stop policy.
  NodeRepository(head: RepositoryData(limits: limits))
func opened*(repository: NodeRepository): bool =
  ## Observe lifecycle without exporting the mutable publication handle.
  repository.head != nil
proc close*(repository: var NodeRepository): RepositoryError =
  ## Release this handle once; independently retained views and copied handles remain valid.
  if repository.head == nil: return RepositoryError.Uninitialized
  repository.head = nil
  RepositoryError.None
proc snapshot*(repository: NodeRepository): RepositoryResult[RepositoryView] =
  ## Retain the current complete version independently of the originating owner.
  let head = repository.head
  if head == nil: return RepositoryResult[RepositoryView](status: RepositoryError.Uninitialized)
  RepositoryResult[RepositoryView](status: RepositoryError.None, completed: RepositoryView(data: head))
func initialized*(view: RepositoryView): bool =
  ## Test a read handle before another storage component accepts ownership of it.
  view.data != nil
proc commitment*(view: RepositoryView): StateTrieCommitment {.requires: view.data != nil.} =
  ## Return copied complete-map metadata, never mutable node storage.
  let data = view.data
  assert data != nil # Keep one contract-proved owner stable for nullable analysis.
  data.commitment
proc generation*(view: RepositoryView): RepositoryGeneration {.requires: view.data != nil.} =
  ## Return the local publication ordinal; it grants no chain authority.
  let data = view.data
  assert data != nil
  data.generation
proc storedNodes*(view: RepositoryView): int {.requires: view.data != nil.} =
  ## Count retained physical addresses, including nodes of prior revisions pending explicit reclamation.
  let data = view.data
  assert data != nil
  data.records.len
proc lookupNode*(view: RepositoryView, digest: StateNodeHash): RepositoryResult[TrieRecord] =
  ## Missing physical data is distinct from an empty child and from a default read view.
  let data = view.data
  if data == nil: return RepositoryResult[TrieRecord](status: RepositoryError.Uninitialized)
  let index = position(data.records, digest)
  if index < 0: return RepositoryResult[TrieRecord](status: RepositoryError.MissingNode)
  RepositoryResult[TrieRecord](status: RepositoryError.None, completed: copyRecord(data.records[index]))

proc publish*(repository: var NodeRepository, expected: RepositoryView,
    batch: TrieExport): RepositoryResult[RepositoryView] =
  ## Preflight storage, validate records/complete target, then publish at one single-threaded point.
  let head = repository.head
  if head == nil: return RepositoryResult[RepositoryView](status: RepositoryError.Uninitialized)
  if expected.data == nil or expected.data != head:
    return RepositoryResult[RepositoryView](status: RepositoryError.StaleView) # Equal roots do not authorize a stale handle.
  if array[32, byte](batch.base) != array[32, byte](head.commitment.root):
    return RepositoryResult[RepositoryView](status: RepositoryError.BaseMismatch)
  if uint64(head.generation) == high(uint64):
    return RepositoryResult[RepositoryView](status: RepositoryError.GenerationExhausted)
  let limits = head.limits
  if uint64(batch.records.len) > uint64(limits.codec.records.records):
    return RepositoryResult[RepositoryView](status: RepositoryError.LimitExceeded)
  var count = head.records.len
  var bytes = head.valueBytes
  for record in batch.records:
    if position(head.records, record.digest) < 0:
      if uint64(count) >= uint64(limits.records) or count >= high(int) div sizeof(TrieRecord):
        return RepositoryResult[RepositoryView](status: RepositoryError.LimitExceeded)
      if uint64(record.payload.len) > uint64(limits.valueBytes)-bytes:
        return RepositoryResult[RepositoryView](status: RepositoryError.LimitExceeded)
      inc count
      bytes += uint64(record.payload.len) # Subtraction proved aggregate retained bytes fit.
  let validated = validateTrieExport(batch, limits.codec)
  if validated != RecordError.None:
    return RepositoryResult[RepositoryView](status: RepositoryError.InvalidRecords,
        recordReason: validated)
  var added = newSeq[TrieRecord](count-head.records.len)
  var next = 0
  for record in batch.records:
    let old = position(head.records, record.digest)
    if old >= 0:
      if not sameRecord(head.records[old], record):
        return RepositoryResult[RepositoryView](status: RepositoryError.RecordConflict)
    else:
      added[next] = copyRecord(record) # Raw transport mutations cannot alter the accepted candidate.
      inc next
  added.sort(compareRecord) # Only newly admitted records require sorting; the published table is already ordered.
  var records = newSeq[TrieRecord](count)
  var prior = 0
  var fresh = 0
  for index in 0..<count:
    # Merge disjoint sorted addresses linearly, retaining old private payload owners without copying bytes.
    if fresh >= added.len or (prior < head.records.len and
        compareHash(head.records[prior].digest, added[fresh].digest) < 0):
      records[index] = head.records[prior]
      inc prior
    else:
      records[index] = added[fresh]
      inc fresh
  var seen = newSeq[bool](records.len)
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let complete = graph(records, StateNodeHash(array[32, byte](batch.root)), 0,
    default(array[31, byte]), limits.codec.trie, seen, counts)
  if complete != RepositoryError.None: return RepositoryResult[RepositoryView](status: complete)
  if counts.entries != batch.entries or counts.nodes != batch.nodes:
    return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph)
  for record in batch.records:
    if not seen[position(records, record.digest)]:
      return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph) # Do not admit unrelated orphan records through a revision batch.
  let data = RepositoryData(records: records, commitment: StateTrieCommitment(root: batch.root,
    entries: int(counts.entries), nodes: counts.nodes), generation: RepositoryGeneration(uint64(
        head.generation)+1),
    valueBytes: bytes, limits: limits)
  repository.head = data # No failed validation can change the prior published owner.
  RepositoryResult[RepositoryView](status: RepositoryError.None, completed: RepositoryView(data: data))

proc restoreStateEntries*(view: RepositoryView, expected: StateRoot,
    limits: StateTrieLimits): RepositoryResult[seq[StateEntry]] =
  ## Copy complete reachable leaves under an independently trusted root, without rehashing them.
  let data = view.data
  if data == nil: return RepositoryResult[seq[StateEntry]](status: RepositoryError.Uninitialized)
  if array[32, byte](data.commitment.root) != array[32, byte](expected):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.RootMismatch) # Local journal/root claims cannot choose authority.
  if uint64(data.commitment.entries) > uint64(limits.items) or data.commitment.nodes > uint64(
      limits.nodes):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.LimitExceeded) # Reject narrower fixed ceilings before traversal scratch.
  var seen = newSeq[bool](data.records.len)
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let checked = graph(data.records, StateNodeHash(array[32, byte](expected)), 0,
    default(array[31, byte]), limits, seen, counts)
  if checked != RepositoryError.None: return RepositoryResult[seq[StateEntry]](status: checked)
  if counts.entries > uint64(high(int) div sizeof(StateEntry)):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.LimitExceeded) # Bound the exact leaf descriptor extent before allocation.
  var entries = newSeq[StateEntry](int(counts.entries))
  var next = 0
  for index, record in data.records:
    if seen[index] and record.kind == TrieRecordKind.Leaf:
      let copied = copyRecord(record)
      entries[next] = StateEntry(key: copied.key, value: copied.payload)
      inc next # Complete graph validation proved the exact reachable leaf count.
  RepositoryResult[seq[StateEntry]](status: RepositoryError.None, completed: entries)

proc restoreFullTrie*(view: RepositoryView, expected: StateRoot,
    limits: FullStateTrieLimits): RepositoryResult[FullStateTrie] =
  ## Reconstruct one immutable trie after trusted complete leaf extraction, preserving mutation ceilings.
  let entries = restoreStateEntries(view, expected, limits.trie)
  if entries.error != RepositoryError.None:
    return RepositoryResult[FullStateTrie](status: entries.error)
  let restored = newFullStateTrie(entries.value, limits)
  if restored.error != TrieError.None:
    return RepositoryResult[FullStateTrie](status: RepositoryError.TrieFailure,
        trieReason: restored.error)
  if array[32, byte](restored.value.commitment.root) != array[32, byte](expected):
    return RepositoryResult[FullStateTrie](status: RepositoryError.RootMismatch)
  RepositoryResult[FullStateTrie](status: RepositoryError.None, completed: restored.value)

proc synchronize*(repository: NodeRepository): RepositoryResult[StorageDurability] =
  ## Memory-only synchronization confirms a live owner, with no survival across process restart.
  if not repository.opened:
    return RepositoryResult[StorageDurability](status: RepositoryError.Uninitialized)
  RepositoryResult[StorageDurability](status: RepositoryError.None,
    completed: StorageDurability.ProcessLifetime)
