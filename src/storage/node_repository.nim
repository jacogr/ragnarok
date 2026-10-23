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
  StoredRecord = ref object ## Private immutable tagged cell owns only its physical form; tables share this ARC owner.
    digest: StateNodeHash
    case kind: TrieRecordKind
    of Leaf:
      key: StateKey              ## Leaf-only bytes never reserve space beside branch edges.
      payload: seq[byte]
    of Branch:
      left, right: StateNodeHash ## Complete physical edges remain distinct from masked JAM hashing.
  ImageRecordStage = object ## Private provisional cells never escape failed encoded-image admission.
    records: seq[StoredRecord]
    limits: RepositoryLimits
    bytes: uint64
    failure: RepositoryError
  RepositoryTable = ref object ## Immutable sorted cell inventories remain independent for changed revisions.
    records: seq[StoredRecord]
    prefixBits: int  ## One private constructor chooses 4/8/12 bits from the bounded inventory size.
    starts: seq[int] ## Derived immutable prefix bounds; full addresses still decide equality.
  RepositoryData = ref object ## Published metadata retains an immutable table, never a previous revision owner.
    table: RepositoryTable
    commitment: StateTrieCommitment
    generation: RepositoryGeneration
    valueBytes: uint64
    limits: RepositoryLimits
  PublicationStage = object ## Privately staged cells preserve codec-before-policy and quota-before-conflict precedence.
    head: RepositoryData
    added, touched: seq[StoredRecord]
    count: int
    bytes: uint64
    quotaExceeded, conflict: bool
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
  RootSlot = object ## Sorting borrowed identities with ordinals preserves first-occurrence output order.
    root: StateRoot
    position: int
  GraphCollection {.pure.} = enum ## Admission avoids collection; extraction and retention request exact positions.
    None, Leaves, Records
  GraphVisit = object ## Traversal scratch optionally collects reachable leaf or complete-record positions.
    seen: seq[uint64]
    leaves: seq[int]
    collect: GraphCollection
  GraphCounts = object ## Explicitly initialized running totals bound untrusted graph traversal.
    entries, nodes, bytes: uint64

func graphWords(count: int): int =
  ## Round a nonnegative inventory length without an overflow-prone count+63 addition.
  count div 64+(if count mod 64 == 0: 0 else: 1)
func marked(bits: seq[uint64], index: int): bool {.inline.} =
  ## Callers supply validated physical positions; unused high bits never authorize another record.
  (bits[index div 64] and (1'u64 shl (index mod 64))) != 0
proc mark(bits: var seq[uint64], index: int) {.inline.} =
  ## Set only an existing validated physical slot in private traversal scratch.
  bits[index div 64] = bits[index div 64] or (1'u64 shl (index mod 64))
proc unmark(bits: var seq[uint64], index: int) {.inline.} =
  ## Per-root reset clears exactly the positions collected by the preceding complete graph traversal.
  bits[index div 64] = bits[index div 64] and not (1'u64 shl (index mod 64))

func error*[T](outcome: RepositoryResult[T]): RepositoryError =
  ## Observe only the selected reason.
  outcome.status
func value*[T](outcome: RepositoryResult[T]): T {.inline,
    requires: outcome.status == RepositoryError.None.} =
  ## Extract only a successful complete operation.
  outcome.completed
proc takeValue*[T](outcome: var RepositoryResult[T]): T {.inline,
    requires: outcome.status == RepositoryError.None.} =
  ## Transfer one successful owner without copying; the consumed result retains no payload or authority.
  result = move(outcome.completed)
  outcome = RepositoryResult[T](status: RepositoryError.Uninitialized)
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
func payloadBytes(record: StoredRecord): int {.inline.} =
  ## Mixed physical inventories count no value bytes for a branch and never read an inactive variant.
  if record.kind == TrieRecordKind.Leaf: record.payload.len
  else: 0
func sameRecord(left: StoredRecord, right: TrieRecord): bool =
  ## Transport preflight has established canonical unused fields; compare every active physical field.
  if left.kind != right.kind or compareHash(left.digest, right.digest) != 0: return false
  if left.kind == TrieRecordKind.Leaf:
    array[31, byte](left.key) == array[31, byte](right.key) and left.payload == right.payload
  else:
    compareHash(left.left, right.left) == 0 and compareHash(left.right, right.right) == 0
proc storeRecord(source: TrieRecord): StoredRecord =
  ## Only fully validated raw records enter this private constructor; mutable leaf payloads still copy.
  if source.kind == TrieRecordKind.Leaf:
    var bytes = newSeq[byte](source.payload.len)
    for index, octet in source.payload:
      bytes[index] = octet # Borrowed input cannot alias immutable admitted ownership.
    result = StoredRecord(kind: TrieRecordKind.Leaf, digest: source.digest,
      key: source.key, payload: bytes)
  else:
    result = StoredRecord(kind: TrieRecordKind.Branch, digest: source.digest,
      left: source.left, right: source.right)
proc storeDecodedRecord(source: var TrieRecord): StoredRecord =
  ## Synchronous local decoding supplies canonical owned records; only leaf payload ownership transfers.
  if source.kind == TrieRecordKind.Leaf:
    result = StoredRecord(kind: TrieRecordKind.Leaf, digest: source.digest,
      key: source.key, payload: move(source.payload))
  else:
    result = StoredRecord(kind: TrieRecordKind.Branch, digest: source.digest,
      left: source.left, right: source.right)
proc prepareImageRecords(stage: var ImageRecordStage, info: RecordCollectionInfo) =
  ## The codec has bounded this exact count; reserve private cell references without repeating input inspection.
  stage.records = newSeqOfCap[StoredRecord](int(info.records))
proc acceptImageRecord(stage: var ImageRecordStage, record: var TrieRecord): bool =
  ## Accumulate private immutable owners while leaving all later codec integrity checks observable.
  if stage.failure != RepositoryError.None: return true
  if uint64(stage.records.len) >= uint64(stage.limits.records) or
      uint64(record.payload.len) > uint64(stage.limits.valueBytes)-stage.bytes:
    stage.failure = RepositoryError.LimitExceeded
    return true # Complete integrity validation still precedes any staged repository refusal.
  stage.bytes += uint64(record.payload.len)
  stage.records.add(storeDecodedRecord(record))
  true
proc copyRecord(source: StoredRecord): TrieRecord =
  ## Reconstruct canonical detached transport, initializing unused fields to zero/empty on both forms.
  if source.kind == TrieRecordKind.Leaf:
    var bytes = newSeq[byte](source.payload.len)
    for index, octet in source.payload:
      bytes[index] = octet # Returned mutable leaf values remain independent of their immutable cell.
    result = TrieRecord(kind: TrieRecordKind.Leaf, digest: source.digest,
      key: source.key, payload: bytes)
  else:
    result = TrieRecord(kind: TrieRecordKind.Branch, digest: source.digest,
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
func hashPrefix(digest: StateNodeHash, bits: int): int =
  ## Bounded private widths use at most two bytes; they never substitute for complete address equality.
  let raw = array[32, byte](digest)
  if bits == 4: int(raw[0]) shr 4
  elif bits == 8: int(raw[0])
  else: (int(raw[0]) shl 4) or (int(raw[1]) shr 4)
proc newRepositoryTable(records: var seq[StoredRecord]): RepositoryTable =
  ## Consume sorted cells; small tables avoid 2 KiB headers while large tables bound typical search intervals.
  let bits = if records.len < 256: 4 elif records.len < 16384: 8 else: 12
  let buckets = 1 shl bits
  result = RepositoryTable(records: move(records), prefixBits: bits, starts: newSeq[int](buckets+1))
  var cursor = 0
  for prefix in 0..buckets:
    # Every chosen directory is bounded by 4097 offsets and retains logarithmic collision behavior.
    while cursor < result.records.len and hashPrefix(result.records[cursor].digest, bits) < prefix:
      inc cursor
    result.starts[prefix] = cursor

proc position(table: RepositoryTable, digest: StateNodeHash): int =
  ## Search one exact derived prefix interval, retaining full 32-byte comparison and logarithmic worst-case work.
  let prefix = hashPrefix(digest, table.prefixBits)
  var first = table.starts[prefix]
  var stop = table.starts[prefix+1]
  while first < stop:
    # Constructor-owned bounds are monotonic and never exceed this immutable inventory's length.
    let middle = first+(stop-first) div 2
    let order = compareHash(table.records[middle].digest, digest)
    if order < 0: first = middle+1
    elif order > 0: stop = middle
    else: return middle
  -1
proc graph(table: RepositoryTable, digest: StateNodeHash, depth: int,
    prefix: array[31, byte], limits: StateTrieLimits, visit: var GraphVisit,
    counts: var GraphCounts): RepositoryError =
  ## Verify complete reachability, bounded acyclic topology and every full key's MSB route.
  if array[32, byte](digest) == default(array[32, byte]): return RepositoryError.None
  let index = position(table, digest)
  if index < 0: return RepositoryError.MissingNode # Partial graphs never become complete revisions.
  if marked(visit.seen, index): return RepositoryError.InvalidGraph # Cycles and repeated logical subtrees cannot represent a full-key map.
  if counts.nodes >= uint64(limits.nodes): return RepositoryError.LimitExceeded
  inc counts.nodes
  mark(visit.seen, index)
  if visit.collect == GraphCollection.Records:
    visit.leaves.add(index) # Retention needs branch and leaf addresses, each once per validated root.
  # Borrow scalar fields directly from the immutable table; a local record would deep-copy payload bytes.
  if table.records[index].kind == TrieRecordKind.Leaf:
    let key = array[31, byte](table.records[index].key)
    for octet in 0..<depth div 8:
      # Whole prefix bytes replace eight identical bit comparisons without reading beyond the key.
      if key[octet] != prefix[octet]: return RepositoryError.InvalidGraph
    let remaining = depth mod 8
    if remaining != 0:
      # Only routed high bits matter; unvisited low key bits remain unconstrained.
      let mask = byte(255 xor ((1 shl (8-remaining))-1))
      if (key[depth div 8] and mask) != (prefix[depth div 8] and mask):
        return RepositoryError.InvalidGraph
    let size = uint64(table.records[index].payload.len)
    if counts.entries >= uint64(limits.items) or size > uint64(limits.perValue) or
        size > uint64(limits.totalValueBytes)-counts.bytes:
      return RepositoryError.LimitExceeded
    if visit.collect == GraphCollection.Leaves: visit.leaves.add(
        index) # Remember validated leaves without scanning historical records later.
    inc counts.entries
    counts.bytes += uint64(table.records[index].payload.len)
  else:
    if depth >= 248: return RepositoryError.InvalidGraph # No branch may read past the full serialized key domain.
    let before = counts.entries
    let left = graph(table, table.records[index].left, depth+1, prefix, limits, visit, counts)
    if left != RepositoryError.None: return left
    var rightPrefix = prefix
    rightPrefix[depth div 8] = rightPrefix[depth div 8] or byte(128 shr (depth mod 8))
    let right = graph(table, table.records[index].right, depth+1, rightPrefix, limits, visit, counts)
    if right != RepositoryError.None: return right
    if counts.entries-before < 2: return RepositoryError.InvalidGraph # Singletons must collapse instead of retaining unary paths.
  RepositoryError.None

proc resetGraph(visit: var GraphVisit) =
  ## Reuse union traversal scratch while clearing every record seen by the preceding complete root.
  for index in visit.leaves:
    unmark(visit.seen, index) # Records collection includes branches and leaves, including empty-root no-ops.
  visit.leaves.setLen(0) # Retain bounded capacity; no previous root can authorize a repeated subtree.

proc newNodeRepository*(limits: RepositoryLimits): NodeRepository =
  ## Open an initialized empty in-memory owner; allocation exhaustion keeps the fail-stop policy.
  var records: seq[StoredRecord] = @[]
  NodeRepository(head: RepositoryData(table: newRepositoryTable(records), limits: limits))
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
proc repositoryLimits*(view: RepositoryView): RepositoryLimits {.requires: view.data != nil.} =
  ## Copy the exact immutable physical/codec policy for bounded consumers; no record storage escapes.
  let data = view.data
  assert data != nil
  data.limits
proc lookupNode*(view: RepositoryView, digest: StateNodeHash): RepositoryResult[TrieRecord] =
  ## Missing physical data is distinct from an empty child and from a default read view.
  let data = view.data
  if data == nil: return RepositoryResult[TrieRecord](status: RepositoryError.Uninitialized)
  let index = position(data.table, digest)
  if index < 0: return RepositoryResult[TrieRecord](status: RepositoryError.MissingNode)
  RepositoryResult[TrieRecord](status: RepositoryError.None, completed: copyRecord(
      data.table.records[index]))

func transportDigest(record: TrieRecord): StateNodeHash =
  ## Private publication traversal projects only the fixed address from an untrusted raw transport.
  record.digest
proc admitPublication[T](repository: var NodeRepository, head: RepositoryData,
    batch: RecordBatchInfo, count: int, bytes: uint64, added: var seq[StoredRecord],
    touched: openArray[T], address: proc(record: T): StateNodeHash {.nimcall.}): RepositoryResult[
        RepositoryView] =
  ## Private bounded cells still need complete target topology and exact touched-record reachability.
  ## Callers preserve independent integrity, head/base/generation and quota/conflict precedence first.
  let limits = head.limits
  if batch.records == 0 and array[32, byte](batch.root) == array[32, byte](
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
  let table = newRepositoryTable(records)
  var visit = GraphVisit(seen: newSeq[uint64](graphWords(table.records.len)))
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let complete = graph(table, StateNodeHash(array[32, byte](batch.root)), 0,
    default(array[31, byte]), limits.codec.trie, visit, counts)
  if complete != RepositoryError.None: return RepositoryResult[RepositoryView](status: complete)
  if counts.entries != batch.entries or counts.nodes != batch.nodes:
    return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph)
  for record in touched:
    if not marked(visit.seen, position(table, address(record))):
      return RepositoryResult[RepositoryView](status: RepositoryError.InvalidGraph) # Do not admit unrelated orphan records through a revision batch.
  let data = RepositoryData(table: table,
      commitment: StateTrieCommitment(root: batch.root,
    entries: int(counts.entries), nodes: counts.nodes), generation: RepositoryGeneration(uint64(
        head.generation)+1),
    valueBytes: bytes, limits: limits)
  repository.head = data # No failed validation can change the prior published owner.
  RepositoryResult[RepositoryView](status: RepositoryError.None, completed: RepositoryView(data: data))


func storedDigest(record: StoredRecord): StateNodeHash =
  ## The private staged-publication path exposes only an immutable cell's fixed physical identity.
  record.digest
proc preparePublicationRecords(stage: var PublicationStage, info: RecordCollectionInfo) =
  ## Whole-input preflight bounded this count; new-cell capacity also respects inherited physical headroom.
  let maximum = uint64(stage.head.limits.records)
  let retained = uint64(stage.head.table.records.len)
  let available = if retained < maximum: maximum-retained else: 0'u64
  stage.added = newSeqOfCap[StoredRecord](int(min(info.records, available)))
  stage.touched = newSeqOfCap[StoredRecord](int(info.records))
proc acceptPublicationRecord(stage: var PublicationStage, record: var TrieRecord): bool =
  ## Continue codec hashing after repository refusal; base/generation and quota precedence resolve afterward.
  let limits = stage.head.limits
  let old = position(stage.head.table.records, record.digest)
  if old < 0:
    if not stage.quotaExceeded:
      let maximum = high(int) div sizeof(TrieRecord)
      let full = uint64(stage.count) >= uint64(limits.records) or stage.count >= maximum
      let payload = uint64(record.payload.len)
      if full or payload > uint64(limits.valueBytes)-stage.bytes:
        stage.quotaExceeded = true
      else:
        inc stage.count
        stage.bytes += uint64(record.payload.len) # A successful subtraction check bounded this aggregate.
  elif not sameRecord(stage.head.table.records[old], record):
    stage.conflict = true
  if stage.quotaExceeded or stage.conflict: return true
  let cell = if old >= 0: stage.head.table.records[old] else: storeDecodedRecord(record)
  if old < 0:
    stage.added.add(cell) # Only new decoded owners enter the private merge inventory.
  stage.touched.add(cell)
  true
proc publishBatch(repository: var NodeRepository, expected: RepositoryView,
    batch: TrieExport): RepositoryResult[RepositoryView] =
  ## Raw mutable transports always require independent integrity and complete graph admission.
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
  var added = newSeqOfCap[StoredRecord](count-head.table.records.len)
  for record in batch.records:
    let old = position(head.table.records, record.digest)
    if old >= 0:
      if not sameRecord(head.table.records[old], record):
        return RepositoryResult[RepositoryView](status: RepositoryError.RecordConflict)
    else:
      added.add(storeRecord(record)) # Append only initialized nonnil cells; raw transport stays detached.
  let info = RecordBatchInfo(base: batch.base, root: batch.root, entries: batch.entries,
    nodes: batch.nodes, records: uint64(batch.records.len), valueBytes: 0)
  admitPublication(repository, head, info, count, bytes, added, batch.records, transportDigest)

proc publish*(repository: var NodeRepository, expected: RepositoryView,
    batch: TrieExport): RepositoryResult[RepositoryView] =
  ## Verify every mutable raw record and complete target before atomic publication.
  publishBatch(repository, expected, batch)

proc publishEncoded*(repository: var NodeRepository, expected: RepositoryView,
    input: openArray[byte]): RepositoryResult[RepositoryView] =
  ## Decode and admit one untrusted serialized revision without rehashing the decoder's owned records.
  ## No public validation flag/token exists; failure leaves the exact prior owner unchanged.
  let head = repository.head
  if head == nil: return RepositoryResult[RepositoryView](status: RepositoryError.Uninitialized)
  if expected.data == nil or expected.data != head:
    return RepositoryResult[RepositoryView](status: RepositoryError.StaleView)
  var stage = PublicationStage(head: head, added: @[], touched: @[],
    count: head.table.records.len, bytes: head.valueBytes, quotaExceeded: false, conflict: false)
  let delivered = visitTrieExport(input, head.limits.codec, stage,
    preparePublicationRecords, acceptPublicationRecord)
  if delivered.error != RecordError.None:
    return RepositoryResult[RepositoryView](status: RepositoryError.InvalidRecords,
      recordReason: delivered.error)
  let info = delivered.value
  if array[32, byte](info.base) != array[32, byte](head.commitment.root):
    return RepositoryResult[RepositoryView](status: RepositoryError.BaseMismatch)
  if uint64(head.generation) == high(uint64):
    return RepositoryResult[RepositoryView](status: RepositoryError.GenerationExhausted)
  if stage.quotaExceeded: return RepositoryResult[RepositoryView](
      status: RepositoryError.LimitExceeded)
  if stage.conflict: return RepositoryResult[RepositoryView](status: RepositoryError.RecordConflict)
  admitPublication(repository, head, info, stage.count, stage.bytes, stage.added, stage.touched, storedDigest)

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
  var visit = GraphVisit(seen: newSeq[uint64](graphWords(data.table.records.len)),
      collect: GraphCollection.Leaves)
  var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
  let checked = graph(data.table, StateNodeHash(array[32, byte](expected)), 0,
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
proc compareRoot(left, right: StateRoot): int =
  ## Root inventories use the same complete lexical identity order as physical addresses.
  compareHash(StateNodeHash(array[32, byte](left)), StateNodeHash(array[32, byte](right)))

proc compareRootSlot(left, right: RootSlot): int =
  ## Equal identities sort by caller position so only the earliest borrowed slot survives.
  let order = compareRoot(left.root, right.root)
  if order != 0: return order # Distinct complete commitments remain independent inventory entries.
  if left.position < right.position: -1
  elif left.position > right.position: 1
  else: 0

proc distinctRoots(roots: openArray[StateRoot]): seq[StateRoot] =
  ## Deduplicate in O(r log r) comparisons without changing caller order or retaining sorting scratch.
  var duplicates = newSeq[uint64](graphWords(roots.len))
  var count = roots.len
  block:
    # The public caller proved this typed extent; retire all ordinal descriptors before output allocation.
    var ordered = newSeq[RootSlot](roots.len)
    for position, root in roots: ordered[position] = RootSlot(root: root, position: position)
    ordered.sort(compareRootSlot)
    for index in 1..<ordered.len:
      if compareRoot(ordered[index-1].root, ordered[index].root) == 0:
        mark(duplicates, ordered[index].position) # Later occurrences never choose output order.
        dec count
  result = newSeq[StateRoot](count)
  var next = 0
  for position, root in roots:
    if not marked(duplicates, position):
      result[next] = root # Copy the original first occurrence, with no alias to caller-mutated storage.
      inc next

proc selectRepositoryRoots*(view: RepositoryView, roots: openArray[StateRoot],
    limit: ElementLimit): RepositoryResult[RepositorySelection] =
  ## Validate an explicit bounded root union including current selection, without changing the source.
  let source = view.data
  if source == nil: return RepositoryResult[RepositorySelection](
      status: RepositoryError.Uninitialized)
  if roots.len == 0: return RepositoryResult[RepositorySelection](
      status: RepositoryError.RootMismatch)
  if uint64(roots.len) > uint64(limit) or roots.len > high(int) div sizeof(RootSlot):
    return RepositoryResult[RepositorySelection](status: RepositoryError.LimitExceeded)
  let unique = distinctRoots(roots) # Count every borrowed slot before coalescing complete identities.
  var selected = false
  for root in unique:
    if array[32, byte](root) == array[32, byte](source.commitment.root):
      selected = true # Required current-root membership still precedes every graph traversal.
  if not selected: return RepositoryResult[RepositorySelection](
      status: RepositoryError.RootMismatch)
  var indices: seq[int] = @[]
  var bytes = 0'u64
  block:
    # Traversal scratch retires before freezing the long-lived exact index inventory.
    var retained = newSeq[uint64](graphWords(source.table.records.len))
    var visit = GraphVisit(seen: newSeq[uint64](graphWords(source.table.records.len)),
        collect: GraphCollection.Records)
    for root in unique:
      # Reuse bounded storage, but reset membership and counters for independent per-root graph checks.
      resetGraph(visit)
      var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
      let checked = graph(source.table, StateNodeHash(array[32, byte](root)), 0,
        default(array[31, byte]), source.limits.codec.trie, visit, counts)
      if checked != RepositoryError.None:
        return RepositoryResult[RepositorySelection](status: checked)
      for index in visit.leaves:
        if not marked(retained, index):
          mark(retained, index)
          indices.add(index)
          bytes += uint64(payloadBytes(source.table.records[
              index])) # Unique source records are bounded by source.valueBytes.
  indices.sort() # Canonicalize the immutable union once; repeated exports/clones can borrow this order.
  var exact = newSeq[int](indices.len)
  for position, index in indices:
    exact[position] = index # Freeze only validated sorted slots; no growable capacity outlives traversal.
  RepositoryResult[RepositorySelection](status: RepositoryError.None,
    completed: RepositorySelection(data: RepositorySelectionData(source: view, roots: unique,
      indices: move(exact), valueBytes: bytes)))

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
  var records = newSeq[TrieRecord](data.indices.len)
  for index, position in data.indices:
    # The immutable selected indices already follow the source's full physical-address order.
    records[index] = copyRecord(source.table.records[position]) # Never export shared mutable payload bytes.
  RepositoryResult[seq[TrieRecord]](status: RepositoryError.None, completed: records)

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

proc imageMetadata(generation: RepositoryGeneration, commitment: StateTrieCommitment,
    inventory: openArray[StateRoot], limits: RepositoryLimits,
        roots: ElementLimit): RepositoryError =
  ## Refuse impossible caller-supplied root metadata before record allocation or integrity work.
  if uint64(generation) == 0 or commitment.entries < 0 or inventory.len == 0:
    return RepositoryError.InvalidGraph
  if uint64(inventory.len) > uint64(roots) or inventory.len > high(int) div sizeof(StateRoot):
    return RepositoryError.LimitExceeded
  if uint64(commitment.entries) > uint64(limits.codec.trie.items) or
      commitment.nodes > uint64(limits.codec.trie.nodes):
    return RepositoryError.LimitExceeded
  if array[32, byte](commitment.root) == default(array[32, byte]):
    if commitment.entries != 0 or commitment.nodes != 0: return RepositoryError.InvalidGraph
  elif commitment.entries == 0 or commitment.nodes < uint64(commitment.entries):
    return RepositoryError.InvalidGraph # A nonempty complete mapping needs at least one node per entry.
  var selected = false
  for index, root in inventory:
    # Root inventories must already be canonical; no serialized input is silently normalized.
    if index > 0 and compareRoot(inventory[index-1], root) >= 0:
      return RepositoryError.InvalidGraph
    if compareRoot(root, commitment.root) == 0: selected = true
  if not selected: return RepositoryError.RootMismatch
  RepositoryError.None

proc admitImageRecords(records: var seq[StoredRecord], bytes: uint64,
    generation: RepositoryGeneration, commitment: StateTrieCommitment, roots: openArray[StateRoot],
    limits: RepositoryLimits): RepositoryResult[NodeRepository] =
  ## Private sorted/integrity-checked cells still need independent graph, inventory and selected-root admission.
  ## Root metadata was checked synchronously; no public caller can supply these private immutable cells.
  let table = newRepositoryTable(records)
  var retained = newSeq[uint64](graphWords(table.records.len))
  var count = 0
  var visit = GraphVisit(seen: newSeq[uint64](graphWords(table.records.len)),
      collect: GraphCollection.Records)
  for root in roots:
    # Serialized roots never inherit prior cycle/route/count authority when scratch storage is reused.
    resetGraph(visit)
    var counts = GraphCounts(entries: 0, nodes: 0, bytes: 0)
    let checked = graph(table, StateNodeHash(array[32, byte](root)), 0,
      default(array[31, byte]), limits.codec.trie, visit, counts)
    if checked != RepositoryError.None: return RepositoryResult[NodeRepository](status: checked)
    if compareRoot(root, commitment.root) == 0:
      if counts.entries != uint64(commitment.entries) or counts.nodes !=
          commitment.nodes:
        return RepositoryResult[NodeRepository](status: RepositoryError.InvalidGraph)
    for index in visit.leaves:
      if not marked(retained, index):
        mark(retained, index)
        inc count # Shared roots need each physical record once, and orphan records never become durable.
  if count != table.records.len: return RepositoryResult[NodeRepository](
      status: RepositoryError.InvalidGraph)
  RepositoryResult[NodeRepository](status: RepositoryError.None,
    completed: NodeRepository(head: RepositoryData(table: table,
      commitment: commitment, generation: generation, valueBytes: bytes,
          limits: limits)))


proc restoreImage(image: RepositoryImage, limits: RepositoryLimits,
    roots: ElementLimit, encoded: ByteLimit): RepositoryResult[NodeRepository] =
  ## Mutable raw images always require independent local integrity and complete graph admission.
  let metadata = imageMetadata(image.generation, image.commitment, image.roots, limits, roots)
  if metadata != RepositoryError.None: return RepositoryResult[NodeRepository](status: metadata)
  let recordCount = image.collection.records.len
  if uint64(recordCount) > uint64(limits.records) or recordCount > high(int) div sizeof(TrieRecord):
    return RepositoryResult[NodeRepository](status: RepositoryError.LimitExceeded)
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
  admitImageRecords(records, bytes, image.generation, image.commitment, image.roots, limits)

proc restoreRepositoryImage*(image: RepositoryImage, limits: RepositoryLimits,
    roots: ElementLimit, encoded: ByteLimit): RepositoryResult[NodeRepository] =
  ## Independently verify every mutable raw record and complete graph before creating an owned repository.
  restoreImage(image, limits, roots, encoded)

proc decodeRepositoryImage*(input: openArray[byte], generation: RepositoryGeneration,
    commitment: StateTrieCommitment, roots: openArray[StateRoot], limits: RepositoryLimits,
    rootLimit: ElementLimit, encoded: ByteLimit): RepositoryResult[NodeRepository] =
  ## Decode a serialized physical collection and admit all complete graphs in one synchronous operation.
  ## Input bytes/root metadata remain borrowed only during this call; success owns independent records.
  ## Integrity failures retain RecordError, while topology/metadata/budget refusals use RepositoryError.
  let metadata = imageMetadata(generation, commitment, roots, limits, rootLimit)
  if metadata != RepositoryError.None: return RepositoryResult[NodeRepository](status: metadata)
  let policy = imageRecordLimits(limits, encoded)
  var stage = ImageRecordStage(records: @[], limits: limits, bytes: 0,
      failure: RepositoryError.None)
  let delivered = visitOrderedRecordCollection(input, policy, stage, prepareImageRecords, acceptImageRecord)
  if delivered.error != RecordError.None:
    return RepositoryResult[NodeRepository](status: RepositoryError.InvalidRecords,
      recordReason: delivered.error)
  if stage.failure != RepositoryError.None:
    return RepositoryResult[NodeRepository](status: stage.failure)
  admitImageRecords(stage.records, stage.bytes, generation, commitment, roots, limits)

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
    let payload = uint64(payloadBytes(source.table.records[index]))
    if payload > uint64(limits.trie.perValue) or fixed > maximum-size:
      return RepositoryResult[int](status: RepositoryError.LimitExceeded)
    size += fixed
    if payload > maximum-size: return RepositoryResult[int](status: RepositoryError.LimitExceeded)
    size += payload # Each addition is proved against the exact host-bounded output ceiling.
  RepositoryResult[int](status: RepositoryError.None, completed: int(size))

proc putCollectionNumber(output: var seq[byte], offset: int, number: uint64) =
  ## Exact collection extent preflight proves the eight little-endian bytes at this private offset.
  for index in 0..<8: output[offset+index] = byte((number shr (index*8)) and 255)

proc putCollectionHash(output: var seq[byte], offset: int, digest: StateNodeHash) =
  ## Copy complete physical identities; branch edges must not use the masked JAM left-child form.
  let raw = array[32, byte](digest)
  for index in 0..<32: output[offset+index] = raw[index]

proc encodeFramedRepositorySelection*(selection: RepositorySelection, limits: RecordLimits,
    prefixBytes, suffixBytes: uint64, outputLimit: ByteLimit): RepositoryResult[seq[byte]] =
  ## Serialize an opaque admitted union between caller-sized, zero-filled frame reservations in one allocation.
  ## Full-width nonnegative extents and the independent whole-output ceiling are checked before narrowing.
  ## Reservations grant no record/graph authority; callers own their framing, checksum and outer interpretation.
  ## No raw records or validation flag are accepted; mutable collections still use the strict record codec.
  ## Failure carries only Uninitialized/LimitExceeded; success owns bytes independent of every source owner.
  let measured = measureRepositorySelection(selection, limits)
  if measured.error != RepositoryError.None:
    return RepositoryResult[seq[byte]](status: measured.error) # No failed extent authorizes output allocation.
  let maximum = min(uint64(outputLimit), uint64(high(int)))
  let bodyBytes = uint64(measured.value)
  if prefixBytes > maximum or suffixBytes > maximum-prefixBytes:
    return RepositoryResult[seq[byte]](status: RepositoryError.LimitExceeded)
  let reserved = prefixBytes+suffixBytes
  if bodyBytes > maximum-reserved:
    return RepositoryResult[seq[byte]](status: RepositoryError.LimitExceeded)
  let data = selection.data
  assert data != nil # Exact measurement succeeded only for a private initialized immutable selection.
  let source = data.source.data
  assert source != nil # Selection construction retained its independently admitted source view.
  const Magic = "RAGNAROK-RECORDS-V1\n"
  var output = newSeq[byte](int(reserved+bodyBytes))
  let prefix = int(prefixBytes)
  for index, character in Magic: output[prefix+index] = byte(character)
  var offset = prefix+Magic.len
  putCollectionNumber(output, offset, uint64(data.indices.len))
  offset += 8
  for position in data.indices:
    # These unique sorted physical cells passed local integrity and complete graph admission before publication.
    let cell = source.table.records[position]
    output[offset] = byte(ord(cell.kind))
    inc offset
    putCollectionHash(output, offset, cell.digest)
    offset += 32
    if cell.kind == TrieRecordKind.Leaf:
      let key = array[31, byte](cell.key)
      for index in 0..<31: output[offset+index] = key[index]
      offset += 31
      putCollectionNumber(output, offset, uint64(cell.payload.len))
      offset += 8
      for octet in cell.payload:
        output[offset] = octet # Copy raw values directly from the stable private owner into the sole final buffer.
        inc offset
    else:
      putCollectionHash(output, offset, cell.left)
      offset += 32
      putCollectionHash(output, offset, cell.right)
      offset += 32 # Physical format retains both complete edges, including the left address's high bit.
  assert offset == output.len-int(suffixBytes) # The writer must end exactly before the reserved suffix.
  RepositoryResult[seq[byte]](status: RepositoryError.None, completed: output)


proc encodeRepositorySelection*(selection: RepositorySelection,
    limits: RecordLimits): RepositoryResult[seq[byte]] =
  ## Preserve canonical body-only encoding, independent ownership and typed preflight failures without reservations.
  encodeFramedRepositorySelection(selection, limits, 0, 0, limits.encoded)

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
  var records = newSeqOfCap[StoredRecord](data.indices.len)
  for position in data.indices:
    # Selection construction proved unique full-address order, independent of borrowed root order.
    records.add(source.table.records[position]) # Share only selected immutable cells; no source view/table is retained.
  let cloned = RepositoryData(table: newRepositoryTable(records),
    commitment: source.commitment, generation: source.generation, valueBytes: data.valueBytes,
        limits: limits)
  RepositoryResult[NodeRepository](status: RepositoryError.None, completed: NodeRepository(head: cloned))
