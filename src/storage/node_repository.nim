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
  RepositoryImage* = object ## Detached untrusted complete-root union preserves the selected durable generation.
    generation*: RepositoryGeneration
    commitment*: StateTrieCommitment
    roots*: seq[StateRoot]
    collection*: RecordCollection
  RepositoryError* {.pure.} = enum ## Errors expose no partial graph, candidate or publication receipt.
    Uninitialized, None, MissingNode, LimitExceeded, StaleView, BaseMismatch,
    InvalidRecords, InvalidGraph, RecordConflict, GenerationExhausted, RootMismatch, TrieFailure, PolicyMismatch
  RepositoryResult*[T] = object ## Only the selected alternatives own a payload or codec diagnostic.
    case status: RepositoryError
    of None: completed: T
    of InvalidRecords: recordReason: RecordError
    of TrieFailure: trieReason: TrieError
    else: discard               # Default and ordinary refusals retain no graph owner.
  StoredRecord = ref object ## Private immutable cell owns bytes once; revision tables share only this ARC owner.
    kind: TrieRecordKind
    digest: StateNodeHash
    key: StateKey
    payload: seq[byte]
    left, right: StateNodeHash
  RepositoryTable = ref object ## Immutable sorted cell inventories remain independent for changed revisions.
    records: seq[StoredRecord]
  RepositoryData = ref object ## Published metadata retains an immutable table, never a previous revision owner.
    table: RepositoryTable
    commitment: StateTrieCommitment
    generation: RepositoryGeneration
    valueBytes: uint64
    limits: RepositoryLimits
  RepositoryView* = object ## Owner-bound immutable physical read view with copied scalar metadata.
    data: nil RepositoryData
  NodeRepository* = object ## Copies are independent updateable handles sharing immutable prior data only.
    head: nil RepositoryData
  RepositorySelectionData = ref object ## Immutable exact-source reachability inventory owns no mutable repository.
    source: RepositoryView
    roots: seq[StateRoot]
    indices: seq[int]
    valueBytes: uint64
  RepositorySelection* = object ## Opaque bounded root union; old plans remain valid after publication/close.
    data: nil RepositorySelectionData
  GraphCollection {.pure.} = enum ## Admission avoids collection; extraction and retention request exact positions.
    None, Leaves, Records
  GraphVisit = object ## Traversal scratch optionally collects reachable leaf or complete-record positions.
    seen: seq[bool]
    leaves: seq[int]
    collect: GraphCollection
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
proc compareRecord(left, right: StoredRecord): int =
  ## Sort records without comparing or copying raw payloads in the comparator.
  compareHash(left.digest, right.digest)
func sameRecord(left: StoredRecord, right: TrieRecord): bool =
  ## A digest collision must not silently replace different physical navigation or values.
  left.kind == right.kind and compareHash(left.digest, right.digest) == 0 and
    array[31, byte](left.key) == array[31, byte](right.key) and left.payload == right.payload and
    compareHash(left.left, right.left) == 0 and compareHash(left.right, right.right) == 0
proc storeRecord(source: TrieRecord): StoredRecord =
  ## Admit copied transport bytes into a private cell that no public API can mutate or expose.
  var bytes = newSeq[byte](source.payload.len)
  for index, octet in source.payload:
    bytes[index] = octet # Borrowed transport must not become a mutable alias of an admitted record.
  StoredRecord(kind: source.kind, digest: source.digest, key: source.key, payload: bytes,
    left: source.left, right: source.right)
proc copyRecord(source: StoredRecord): TrieRecord =
  ## Deep-copy only mutable byte storage; fixed addresses and keys copy by value.
  var bytes = newSeq[byte](source.payload.len)
  for i, octet in source.payload: bytes[i] = octet
  TrieRecord(kind: source.kind, digest: source.digest, key: source.key, payload: bytes,
    left: source.left, right: source.right)
proc position(records: seq[StoredRecord], digest: StateNodeHash): int =
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
proc graph(records: seq[StoredRecord], digest: StateNodeHash, depth: int,
    prefix: array[31, byte], limits: StateTrieLimits, visit: var GraphVisit,
    counts: var GraphCounts): RepositoryError =
  ## Verify complete reachability, bounded acyclic topology and every full key's MSB route.
  if array[32, byte](digest) == default(array[32, byte]): return RepositoryError.None
  let index = position(records, digest)
  if index < 0: return RepositoryError.MissingNode # Partial graphs never become complete revisions.
  if visit.seen[index]: return RepositoryError.InvalidGraph # Cycles and repeated logical subtrees cannot represent a full-key map.
  if counts.nodes >= uint64(limits.nodes): return RepositoryError.LimitExceeded
  inc counts.nodes
  visit.seen[index] = true
  if visit.collect == GraphCollection.Records:
    visit.leaves.add(index) # Retention needs branch and leaf addresses, each once per validated root.
  # Borrow scalar fields directly from the immutable table; a local record would deep-copy payload bytes.
  if records[index].kind == TrieRecordKind.Leaf:
    let key = array[31, byte](records[index].key)
    for bit in 0..<depth:
      let mask = byte(128 shr (bit mod 8))
      if (key[bit div 8] and mask) != (prefix[bit div 8] and mask):
        return RepositoryError.InvalidGraph # A locally valid node at the wrong path is not a valid trie.
    let size = uint64(records[index].payload.len)
    if counts.entries >= uint64(limits.items) or size > uint64(limits.perValue) or
        size > uint64(limits.totalValueBytes)-counts.bytes:
      return RepositoryError.LimitExceeded
    if visit.collect == GraphCollection.Leaves: visit.leaves.add(
        index) # Remember validated leaves without scanning historical records later.
    inc counts.entries
    counts.bytes += uint64(records[index].payload.len)
  else:
    if depth >= 248: return RepositoryError.InvalidGraph # No branch may read past the full serialized key domain.
    let before = counts.entries
    let left = graph(records, records[index].left, depth+1, prefix, limits, visit, counts)
    if left != RepositoryError.None: return left
    var rightPrefix = prefix
    rightPrefix[depth div 8] = rightPrefix[depth div 8] or byte(128 shr (depth mod 8))
    let right = graph(records, records[index].right, depth+1, rightPrefix, limits, visit, counts)
    if right != RepositoryError.None: return right
    if counts.entries-before < 2: return RepositoryError.InvalidGraph # Singletons must collapse instead of retaining unary paths.
  RepositoryError.None

proc newNodeRepository*(limits: RepositoryLimits): NodeRepository =
  ## Open an initialized empty in-memory owner; allocation exhaustion keeps the fail-stop policy.
  NodeRepository(head: RepositoryData(table: RepositoryTable(records: @[]), limits: limits))
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
  data.table.records.len
proc lookupNode*(view: RepositoryView, digest: StateNodeHash): RepositoryResult[TrieRecord] =
  ## Missing physical data is distinct from an empty child and from a default read view.
  let data = view.data
  if data == nil: return RepositoryResult[TrieRecord](status: RepositoryError.Uninitialized)
  let index = position(data.table.records, digest)
  if index < 0: return RepositoryResult[TrieRecord](status: RepositoryError.MissingNode)
  RepositoryResult[TrieRecord](status: RepositoryError.None, completed: copyRecord(
      data.table.records[index]))

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
  var count = head.table.records.len
  var bytes = head.valueBytes
  for record in batch.records:
    if position(head.table.records, record.digest) < 0:
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
  if batch.records.len == 0 and array[32, byte](batch.root) == array[32, byte](
      head.commitment.root):
    # Immutable current graphs need no traversal or table copy; exact metadata remains mandatory.
    if batch.entries != uint64(head.commitment.entries) or batch.nodes != head.commitment.nodes:
      return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph)
    let data = RepositoryData(table: head.table, commitment: head.commitment,
      generation: RepositoryGeneration(uint64(head.generation)+1), valueBytes: head.valueBytes,
      limits: limits)
    repository.head = data # A new exact view identity/generation still invalidates old publication handles.
    return RepositoryResult[RepositoryView](status: RepositoryError.None,
      completed: RepositoryView(data: data))
  var added = newSeqOfCap[StoredRecord](count-head.table.records.len)
  for record in batch.records:
    let old = position(head.table.records, record.digest)
    if old >= 0:
      if not sameRecord(head.table.records[old], record):
        return RepositoryResult[RepositoryView](status: RepositoryError.RecordConflict)
    else:
      added.add(storeRecord(record)) # Append only initialized nonnil cells; raw transport stays detached.
  added.sort(compareRecord) # Only newly admitted records require sorting; the published table is already ordered.
  var records = newSeqOfCap[StoredRecord](count)
  var prior = 0
  var fresh = 0
  for index in 0..<count:
    # Merge disjoint sorted addresses linearly, retaining old private payload owners without copying bytes.
    if fresh >= added.len or (prior < head.table.records.len and
        compareHash(head.table.records[prior].digest, added[fresh].digest) < 0):
      records.add(head.table.records[prior])
      inc prior
    else:
      records.add(added[fresh])
      inc fresh
  var visit = GraphVisit(seen: newSeq[bool](records.len))
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let complete = graph(records, StateNodeHash(array[32, byte](batch.root)), 0,
    default(array[31, byte]), limits.codec.trie, visit, counts)
  if complete != RepositoryError.None: return RepositoryResult[RepositoryView](status: complete)
  if counts.entries != batch.entries or counts.nodes != batch.nodes:
    return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph)
  for record in batch.records:
    if not visit.seen[position(records, record.digest)]:
      return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph) # Do not admit unrelated orphan records through a revision batch.
  let data = RepositoryData(table: RepositoryTable(records: records),
      commitment: StateTrieCommitment(root: batch.root,
    entries: int(counts.entries), nodes: counts.nodes), generation: RepositoryGeneration(uint64(
        head.generation)+1),
    valueBytes: bytes, limits: limits)
  repository.head = data # No failed validation can change the prior published owner.
  RepositoryResult[RepositoryView](status: RepositoryError.None, completed: RepositoryView(data: data))

proc collectStateEntries(view: RepositoryView, expected: StateRoot,
    limits: StateTrieLimits, selected: bool): RepositoryResult[seq[StateEntry]] =
  ## Copy complete reachable leaves under an independently trusted root, without rehashing them.
  let data = view.data
  if data == nil: return RepositoryResult[seq[StateEntry]](status: RepositoryError.Uninitialized)
  if selected and array[32, byte](data.commitment.root) != array[32, byte](expected):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.RootMismatch) # Local journal/root claims cannot choose authority.
  if selected and (uint64(data.commitment.entries) > uint64(limits.items) or data.commitment.nodes >
      uint64(limits.nodes)):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.LimitExceeded) # Reject narrower fixed ceilings before traversal scratch.
  var visit = GraphVisit(seen: newSeq[bool](data.table.records.len),
      collect: GraphCollection.Leaves)
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let checked = graph(data.table.records, StateNodeHash(array[32, byte](expected)), 0,
    default(array[31, byte]), limits, visit, counts)
  if checked != RepositoryError.None: return RepositoryResult[seq[StateEntry]](status: checked)
  if counts.entries > uint64(high(int) div sizeof(StateEntry)):
    return RepositoryResult[seq[StateEntry]](status: RepositoryError.LimitExceeded) # Bound the exact leaf descriptor extent before allocation.
  var entries = newSeq[StateEntry](int(counts.entries))
  var next = 0
  for index in visit.leaves:
    # Left-before-right traversal yields full keys in canonical order, independent of physical history.
    let copied = copyRecord(data.table.records[index])
    entries[next] = StateEntry(key: copied.key, value: copied.payload)
    inc next # Complete graph validation proved the exact reachable leaf count.
  RepositoryResult[seq[StateEntry]](status: RepositoryError.None, completed: entries)

proc restoreStateEntries*(view: RepositoryView, expected: StateRoot,
    limits: StateTrieLimits): RepositoryResult[seq[StateEntry]] =
  ## Extract only the selected complete mapping under independently supplied root authority.
  collectStateEntries(view, expected, limits, true)
proc restoreHistoricalStateEntries*(view: RepositoryView, expected: StateRoot,
    limits: StateTrieLimits): RepositoryResult[seq[StateEntry]] =
  ## Verify and copy a complete explicitly selected historical root without changing the current head.
  ## Presence of physical records grants no chain/finality authority; the caller must supply that binding.
  collectStateEntries(view, expected, limits, false)

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

func initialized*(selection: RepositorySelection): bool =
  ## Query success ownership before accessing a retention plan's scalar observations.
  selection.data != nil
func matches*(selection: RepositorySelection, view: RepositoryView): bool =
  ## Compare exact immutable source owners, never just a root or local generation.
  let data = selection.data
  data != nil and data.source.data == view.data
proc retainedNodes*(selection: RepositorySelection): int {.requires: selection.initialized.} =
  ## Count unique physical records needed by the selected root union.
  let data = selection.data
  assert data != nil
  data.indices.len
proc retainedValueBytes*(selection: RepositorySelection): uint64 {.requires: selection.initialized.} =
  ## Count unique retained leaf payload bytes, without multiplying shared nodes across roots.
  let data = selection.data
  assert data != nil
  data.valueBytes
proc reclaimableNodes*(selection: RepositorySelection): int {.requires: selection.initialized.} =
  ## Count source records outside the root union; this observation performs no reclamation.
  let data = selection.data
  assert data != nil
  data.source.storedNodes-data.indices.len
proc reclaimableValueBytes*(selection: RepositorySelection): uint64 {.requires: selection.initialized.} =
  ## Count source payload bytes outside the union, under the source's already checked total.
  let data = selection.data
  assert data != nil
  let source = data.source.data
  assert source != nil
  source.valueBytes-data.valueBytes
proc retainedRoots*(selection: RepositorySelection): seq[
    StateRoot] {.requires: selection.initialized.} =
  ## Return detached root identities; their presence grants no chain or finality authority.
  let data = selection.data
  assert data != nil
  var roots = newSeq[StateRoot](data.roots.len)
  for index, root in data.roots: roots[index] = root # No mutable alias to the accepted plan escapes.
  roots
proc selectRepositoryRoots*(view: RepositoryView, roots: openArray[StateRoot],
    limit: ElementLimit): RepositoryResult[RepositorySelection] =
  ## Validate an explicit bounded root union including current selection, without changing the source.
  let source = view.data
  if source == nil: return RepositoryResult[RepositorySelection](
      status: RepositoryError.Uninitialized)
  if roots.len == 0: return RepositoryResult[RepositorySelection](
      status: RepositoryError.RootMismatch)
  if uint64(roots.len) > uint64(limit) or roots.len > high(int) div sizeof(StateRoot):
    return RepositoryResult[RepositorySelection](status: RepositoryError.LimitExceeded)
  var selected = false
  var unique: seq[StateRoot] = @[]
  for root in roots:
    # Count every borrowed slot against the ceiling, then coalesce equal root identities.
    if array[32, byte](root) == array[32, byte](source.commitment.root): selected = true
    var duplicate = false
    for prior in unique:
      if array[32, byte](prior) == array[32, byte](root): duplicate = true
    if not duplicate: unique.add(root)
  if not selected: return RepositoryResult[RepositorySelection](
      status: RepositoryError.RootMismatch)
  var retained = newSeq[bool](source.table.records.len)
  var indices: seq[int] = @[]
  var bytes = 0'u64
  for root in unique:
    # Each complete root gets independent cycle/route checks; shared records count once in the union.
    var visit = GraphVisit(seen: newSeq[bool](source.table.records.len),
        collect: GraphCollection.Records)
    var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
    let checked = graph(source.table.records, StateNodeHash(array[32, byte](root)), 0,
      default(array[31, byte]), source.limits.codec.trie, visit, counts)
    if checked != RepositoryError.None:
      return RepositoryResult[RepositorySelection](status: checked)
    for index in visit.leaves:
      if not retained[index]:
        retained[index] = true
        indices.add(index)
        bytes += uint64(source.table.records[index].payload.len) # Unique source records are bounded by source.valueBytes.
  RepositoryResult[RepositorySelection](status: RepositoryError.None,
    completed: RepositorySelection(data: RepositorySelectionData(source: view, roots: unique,
      indices: indices, valueBytes: bytes)))

proc commitment*(selection: RepositorySelection): StateTrieCommitment {.requires: selection.initialized.} =
  ## Copy the selected current complete commitment from this plan's immutable source.
  let data = selection.data
  assert data != nil
  data.source.commitment
proc generation*(selection: RepositorySelection): RepositoryGeneration {.requires: selection.initialized.} =
  ## Copy the source generation without creating a new publication or chain identity.
  let data = selection.data
  assert data != nil
  data.source.generation
proc exportRepositorySelection*(selection: RepositorySelection,
    limits: TrieExportLimits): RepositoryResult[seq[TrieRecord]] =
  ## Detach the validated root union in physical address order after exact descriptor/payload preflight.
  ## This multi-root union is not a single-target TrieExport and cannot bypass its orphan checks.
  let data = selection.data
  if data == nil: return RepositoryResult[seq[TrieRecord]](status: RepositoryError.Uninitialized)
  let maximum = min(uint64(limits.records), uint64(high(int) div sizeof(TrieRecord)))
  if uint64(data.indices.len) > maximum or data.valueBytes > uint64(limits.valueBytes):
    return RepositoryResult[seq[TrieRecord]](status: RepositoryError.LimitExceeded)
  let source = data.source.data
  assert source != nil
  var indices = newSeq[int](data.indices.len)
  for index, position in data.indices: indices[index] = position # Sorting must not mutate the immutable plan.
  indices.sort() # Source record indices have the same unique lexical order as their full physical addresses.
  var records = newSeq[TrieRecord](indices.len)
  for index, position in indices:
    records[index] = copyRecord(source.table.records[position]) # Never export shared mutable payload bytes.
  RepositoryResult[seq[TrieRecord]](status: RepositoryError.None, completed: records)

proc compareRoot(left, right: StateRoot): int =
  ## Canonical root inventories use the same fixed lexical byte order as physical addresses.
  compareHash(StateNodeHash(array[32, byte](left)), StateNodeHash(array[32, byte](right)))
proc exportRepositoryImage*(selection: RepositorySelection, limits: TrieExportLimits,
    roots: ElementLimit): RepositoryResult[RepositoryImage] =
  ## Bound and detach a validated union, preserving current metadata and ordering its unique root set.
  let data = selection.data
  if data == nil: return RepositoryResult[RepositoryImage](status: RepositoryError.Uninitialized)
  if uint64(data.roots.len) > uint64(roots):
    return RepositoryResult[RepositoryImage](status: RepositoryError.LimitExceeded)
  if uint64(data.source.generation) == 0:
    return RepositoryResult[RepositoryImage](status: RepositoryError.InvalidGraph)
  let exported = exportRepositorySelection(selection, limits)
  if exported.error != RepositoryError.None:
    return RepositoryResult[RepositoryImage](status: exported.error)
  var ordered = selection.retainedRoots
  ordered.sort(compareRoot)
  RepositoryResult[RepositoryImage](status: RepositoryError.None,
    completed: RepositoryImage(generation: data.source.generation,
      commitment: data.source.commitment,
      roots: ordered, collection: RecordCollection(records: exported.value)))
proc imageRecordLimits(limits: RepositoryLimits, encoded: ByteLimit): RecordLimits =
  ## Complete images use aggregate physical union budgets rather than one target's export ceiling.
  result = limits.codec
  result.records = TrieExportLimits(records: TrieNodeLimit(uint64(limits.records)),
    valueBytes: limits.valueBytes)
  result.encoded = encoded

proc restoreImage(image: RepositoryImage, limits: RepositoryLimits,
    roots: ElementLimit, encoded: ByteLimit, decoded: bool): RepositoryResult[NodeRepository] =
  ## Private callers either validate raw records here or just decoded them under these exact limits.
  ## No public entry point accepts the decoded flag; all graph/ordering/reachability checks are shared.
  if uint64(image.generation) == 0 or image.commitment.entries < 0 or image.roots.len == 0:
    return RepositoryResult[NodeRepository](status: RepositoryError.InvalidGraph)
  if uint64(image.roots.len) > uint64(roots) or image.roots.len > high(int) div sizeof(StateRoot):
    return RepositoryResult[NodeRepository](status: RepositoryError.LimitExceeded)
  let recordCount = image.collection.records.len
  if uint64(recordCount) > uint64(limits.records) or recordCount > high(int) div sizeof(TrieRecord):
    return RepositoryResult[NodeRepository](status: RepositoryError.LimitExceeded)
  var selected = false
  for index, root in image.roots:
    if index > 0 and compareRoot(image.roots[index-1], root) >= 0:
      return RepositoryResult[NodeRepository](status: RepositoryError.InvalidGraph) # Root inventories are unique and canonical.
    if compareRoot(root, image.commitment.root) == 0: selected = true
  if not selected: return RepositoryResult[NodeRepository](status: RepositoryError.RootMismatch)
  if not decoded:
    # Mutable raw images have no integrity authority, even if a caller previously decoded them.
    let validated = validateRecordCollection(image.collection, imageRecordLimits(limits, encoded))
    if validated != RecordError.None:
      return RepositoryResult[NodeRepository](status: RepositoryError.InvalidRecords,
        recordReason: validated)
  var records = newSeqOfCap[StoredRecord](recordCount)
  var bytes = 0'u64
  for index, record in image.collection.records:
    if index > 0 and compareHash(image.collection.records[index-1].digest, record.digest) >= 0:
      return RepositoryResult[NodeRepository](status: RepositoryError.InvalidGraph) # Persisted address order is exact, not silently normalized.
    records.add(storeRecord(record))
    bytes += uint64(record.payload.len) # Collection preflight proved the aggregate physical byte bound.
  var retained = newSeq[bool](records.len)
  var count = 0
  for root in image.roots:
    var visit = GraphVisit(seen: newSeq[bool](records.len), collect: GraphCollection.Records)
    var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
    let checked = graph(records, StateNodeHash(array[32, byte](root)), 0,
      default(array[31, byte]), limits.codec.trie, visit, counts)
    if checked != RepositoryError.None: return RepositoryResult[NodeRepository](status: checked)
    if compareRoot(root, image.commitment.root) == 0:
      if counts.entries != uint64(image.commitment.entries) or counts.nodes !=
          image.commitment.nodes:
        return RepositoryResult[NodeRepository](status: RepositoryError.InvalidGraph)
    for index in visit.leaves:
      if not retained[index]:
        retained[index] = true
        inc count # Shared roots need each physical record once, and orphan records never become durable.
  if count != records.len: return RepositoryResult[NodeRepository](
      status: RepositoryError.InvalidGraph)
  RepositoryResult[NodeRepository](status: RepositoryError.None,
    completed: NodeRepository(head: RepositoryData(table: RepositoryTable(records: records),
      commitment: image.commitment, generation: image.generation, valueBytes: bytes,
          limits: limits)))

proc restoreRepositoryImage*(image: RepositoryImage, limits: RepositoryLimits,
    roots: ElementLimit, encoded: ByteLimit): RepositoryResult[NodeRepository] =
  ## Independently verify every mutable raw record and complete graph before creating an owned repository.
  restoreImage(image, limits, roots, encoded, false)

proc decodeRepositoryImage*(input: openArray[byte], generation: RepositoryGeneration,
    commitment: StateTrieCommitment, roots: openArray[StateRoot], limits: RepositoryLimits,
    rootLimit: ElementLimit, encoded: ByteLimit): RepositoryResult[NodeRepository] =
  ## Decode a serialized physical collection and admit all complete graphs in one synchronous operation.
  ## Input bytes/root metadata remain borrowed only during this call; success owns independent records.
  ## Integrity failures retain RecordError, while topology/metadata/budget refusals use RepositoryError.
  if uint64(roots.len) > uint64(rootLimit) or roots.len > high(int) div sizeof(StateRoot):
    return RepositoryResult[NodeRepository](status: RepositoryError.LimitExceeded)
  let decoded = decodeRecordCollection(input, imageRecordLimits(limits, encoded))
  if decoded.error != RecordError.None:
    return RepositoryResult[NodeRepository](status: RepositoryError.InvalidRecords,
      recordReason: decoded.error)
  var ownedRoots = newSeq[StateRoot](roots.len)
  for index, root in roots:
    ownedRoots[index] = root # Bounded scalar copies cannot retain mutable caller metadata.
  let image = RepositoryImage(generation: generation, commitment: commitment,
    roots: ownedRoots, collection: decoded.value)
  restoreImage(image, limits, rootLimit, encoded, true)

proc repositoryLimits*(selection: RepositorySelection): RepositoryLimits {.requires: selection.initialized.} =
  ## Copy inherited scalar policy without exposing physical records or an updateable source handle.
  let data = selection.data
  assert data != nil
  let source = data.source.data
  assert source != nil
  source.limits

proc retainedRootCount*(selection: RepositorySelection): int {.requires: selection.initialized.} =
  ## Count roots without allocating a detached root inventory.
  let data = selection.data
  assert data != nil
  data.roots.len
proc measureRepositorySelection*(selection: RepositorySelection,
    limits: RecordLimits): RepositoryResult[int] =
  ## Preflight the exact record-collection extent without hashing, detaching records or allocating output.
  let data = selection.data
  if data == nil: return RepositoryResult[int](status: RepositoryError.Uninitialized)
  if uint64(data.indices.len) > uint64(limits.records.records) or data.valueBytes > uint64(
      limits.records.valueBytes):
    return RepositoryResult[int](status: RepositoryError.LimitExceeded)
  let empty = measureRecordCollection(default(RecordCollection), limits)
  if empty.error != RecordError.None: return RepositoryResult[int](
      status: RepositoryError.LimitExceeded)
  var size = uint64(empty.value)
  let maximum = min(uint64(limits.encoded), uint64(high(int)))
  let source = data.source.data
  assert source != nil
  for index in data.indices:
    let fixed = if source.table.records[index].kind == TrieRecordKind.Leaf: 72'u64 else: 97'u64
    let payload = uint64(source.table.records[index].payload.len)
    if payload > uint64(limits.trie.perValue) or fixed > maximum-size:
      return RepositoryResult[int](status: RepositoryError.LimitExceeded)
    size += fixed
    if payload > maximum-size: return RepositoryResult[int](status: RepositoryError.LimitExceeded)
    size += payload # Each addition is proved against the exact host-bounded output ceiling.
  RepositoryResult[int](status: RepositoryError.None, completed: int(size))

proc cloneRepositorySelection*(selection: RepositorySelection,
    limits: RepositoryLimits): RepositoryResult[NodeRepository] =
  ## Materialize an independent selected table sharing private immutable records, without rehashing or payload copies.
  let data = selection.data
  if data == nil: return RepositoryResult[NodeRepository](status: RepositoryError.Uninitialized)
  let source = data.source.data
  assert source != nil
  let inherited = source.limits.codec.trie
  let required = limits.codec.trie
  let oldPolicy = [uint64(inherited.items), uint64(inherited.nodes),
    uint64(inherited.perValue), uint64(inherited.totalValueBytes)]
  let newPolicy = [uint64(required.items), uint64(required.nodes),
    uint64(required.perValue), uint64(required.totalValueBytes)]
  if oldPolicy != newPolicy:
    return RepositoryResult[NodeRepository](status: RepositoryError.PolicyMismatch)
  let maximum = min(uint64(limits.records), uint64(high(int) div sizeof(TrieRecord)))
  if uint64(data.indices.len) > maximum or data.valueBytes > uint64(limits.valueBytes):
    return RepositoryResult[NodeRepository](status: RepositoryError.LimitExceeded)
  var indices = newSeq[int](data.indices.len)
  for index, position in data.indices:
    indices[index] = position # Keep the immutable selection's traversal order untouched.
  indices.sort() # Complete table order must remain canonical for physical lookup and subsequent publication.
  var records = newSeqOfCap[StoredRecord](indices.len)
  for position in indices:
    records.add(source.table.records[position]) # Share only selected immutable cells; no source view/table is retained.
  let cloned = RepositoryData(table: RepositoryTable(records: records),
    commitment: source.commitment, generation: source.generation, valueBytes: data.valueBytes,
        limits: limits)
  RepositoryResult[NodeRepository](status: RepositoryError.None, completed: NodeRepository(head: cloned))
