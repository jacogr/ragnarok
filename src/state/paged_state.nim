# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete StateStore snapshot transport adopts the paged full backend with explicit resident/export budgets.
## Native owners remain caller-owned; no light evidence, application context or root trust is inferred.
import std/[algorithm, assertions]
import ./store
import ../storage/[full_paged_codec, full_paged_stream, full_paged_store, full_paged_build,
  full_state_trie, node_records, paged_codec, durability]
import ../codec/[bounded, state_layout, state_trie]

type
  PagedStateLimits* = object ## Count all input snapshots and staging records/values before deduplication; final geometry has its own ceiling.
    roots*: ElementLimit
    staging*: TrieExportLimits
    dataset*: PagedLimits
  PagedStateError* {.pure.} = enum ## Failed/default alternatives expose no prepared bytes, native success or partial complete-map owner.
    Uninitialized, None, LimitExceeded, LengthOverflow, PolicyMismatch, RootMismatch, StaleView,
    RecordConflict, StateFailure, ExportFailure, GeometryFailure, CodecFailure, NativeFailure
  PagedStateResult*[T] = object ## Exact selected stage diagnostics stay separate from successful immutable transport/store payloads.
    case status: PagedStateError
    of None: completed: T
    of StateFailure: stateCause: StateStoreError
    of ExportFailure: exportCause: TrieError
    of GeometryFailure: geometryCause: PagedCodecError
    of CodecFailure: codecCause: FullPagedError
    of NativeFailure: nativeCause: FullPagedNativeResult[bool]
    else: discard
  PreparedData = ref object ## Acyclic immutable transport contains no native owner, callback or caller-owned mutable byte buffer.
    root: StateRoot
    roots: seq[FullPagedRoot]
    records: seq[TrieRecord]
    payload, fileBytes: uint64
  PreparedPagedState* = object ## Cheap copies retain one bounded private record union for synchronous publication or exact replay.
    data: nil PreparedData
  RestoreStage = ref object ## Private consumer copies stay unpublished until full streaming and independent complete-map commitment succeed.
    entries: seq[StateEntry]
    next: int
    bytes: uint64
    limits: StateStoreLimits
    reason: StateStoreError
func error*[T](outcome: PagedStateResult[T]): PagedStateError =
  ## Inspect only the selected transport/restore stage.
  outcome.status
func value*[T](outcome: PagedStateResult[T]): T {.inline, requires: outcome.status ==
    PagedStateError.None.} =
  ## Only complete success exposes an immutable transport, native receipt or ordinary complete StateStore.
  outcome.completed
func stateError*[T](outcome: PagedStateResult[T]): StateStoreError {.requires: outcome.status ==
    PagedStateError.StateFailure.} =
  ## Preserve actual complete-store construction and callback-copy policy refusals.
  outcome.stateCause
func exportError*[T](outcome: PagedStateResult[T]): TrieError {.requires: outcome.status ==
    PagedStateError.ExportFailure.} =
  ## Preserve the original bounded full-trie export diagnostic.
  outcome.exportCause
func geometryError*[T](outcome: PagedStateResult[T]): PagedCodecError {.requires: outcome.status ==
    PagedStateError.GeometryFailure.} =
  ## Encoded output geometry is independent of resident transport staging policy.
  outcome.geometryCause
func codecError*[T](outcome: PagedStateResult[T]): FullPagedError {.requires: outcome.status ==
    PagedStateError.CodecFailure.} =
  ## Selected manifest encoding failures never become stale-view or root-trust decisions.
  outcome.codecCause
func nativeFailure*[T](outcome: PagedStateResult[T]): FullPagedNativeResult[
    bool] {.requires: outcome.status == PagedStateError.NativeFailure.} =
  ## The guarded native failure conversion contains reasons alone, never an erased publication success.
  outcome.nativeCause
func refused[T](reason: PagedStateError): PagedStateResult[T] =
  ## Plain lifecycle/policy/conflict refusals contain no usable transport prefix.
  PagedStateResult[T](status: reason)
func nativeFailed[T, U](outcome: FullPagedNativeResult[U]): PagedStateResult[
    T] {.requires: outcome.error != FullPagedNativeError.None.} =
  ## Composite errors retain the exact original native stage and subordinate causes.
  PagedStateResult[T](status: PagedStateError.NativeFailure, nativeCause: outcome.failure)
func initialized*(prepared: PreparedPagedState): bool =
  ## Default transport cannot authorize any producer or native publication.
  prepared.data != nil
proc root*(prepared: PreparedPagedState): StateRoot {.requires: prepared.data != nil.} =
  ## This complete-map commitment still needs independent caller trust at native initialization.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  data.root
proc recordCount*(prepared: PreparedPagedState): uint64 {.requires: prepared.data != nil.} =
  ## Final unique physical records differ from the bounded staging count across retained snapshots.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  uint64(data.records.len)
proc payloadBytes*(prepared: PreparedPagedState): uint64 {.requires: prepared.data != nil.} =
  ## Canonical full-record transport extent excludes section padding and page tree.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  data.payload
proc byteLength*(prepared: PreparedPagedState): uint64 {.requires: prepared.data != nil.} =
  ## Return the exact derived final physical artifact extent.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  data.fileBytes
proc roots*(prepared: PreparedPagedState): seq[FullPagedRoot] {.requires: prepared.data != nil.} =
  ## Detach mutable scalar claims; caller mutations cannot alter future producer/publication behavior.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  result = newSeq[FullPagedRoot](data.roots.len)
  for index in 0..<result.len: result[index] = data.roots[index] # At most64 immutable root claims.
proc compareRecord(a, b: TrieRecord): int =
  ## Sorting complete hashes never masks physical left-child identity.
  compareFullHash(array[32, byte](a.digest), array[32, byte](b.digest))
proc compareRoot(a, b: FullPagedRoot): int =
  ## Full header root inventory has one strict canonical ordering.
  compareFullHash(array[32, byte](a.root), array[32, byte](b.root))
proc sameRecord(a, b: TrieRecord): bool =
  ## Equal protocol addresses cannot choose between conflicting complete physical transports.
  a.kind == b.kind and array[31, byte](a.key) == array[31, byte](b.key) and
    array[32, byte](a.left) == array[32, byte](b.left) and
    array[32, byte](a.right) == array[32, byte](b.right) and a.payload == b.payload
proc preparePagedState*(source: StateStoreSnapshot, history: openArray[StateStoreSnapshot],
    limits: PagedStateLimits): PagedStateResult[PreparedPagedState] =
  ## Preflight every borrowed immutable source before allocating copied record/value transport; retain no original map owners.
  let current = forkStateStore(source)
  if current.error != StateStoreError.None:
    return PagedStateResult[PreparedPagedState](status: PagedStateError.StateFailure,
        stateCause: current.error)
  if history.len >= FullPagedMaxRoots or uint64(history.len) >= uint64(limits.roots):
    return refused[PreparedPagedState](PagedStateError.LimitExceeded)
  var claims = newSeq[FullPagedRoot](history.len+1)
  var stagedRecords, stagedValues = 0'u64
  for index in 0..history.len:
    # All full maps use the same inherited policy; defaults and partial evidence have no compatible snapshot identity.
    let snapshot = if index < history.len: history[index] else: source
    if not sameStateStorePolicy(source, snapshot):
      return refused[PreparedPagedState](PagedStateError.PolicyMismatch)
    let committed = snapshot.commitment
    if committed.nodes > uint64(limits.staging.records)-stagedRecords:
      return refused[PreparedPagedState](PagedStateError.LimitExceeded)
    stagedRecords += committed.nodes
    var bytes = 0'u64
    for ordinal in 0..<committed.entries:
      # Read only immutable metadata lengths before exporting/copying any value buffers.
      let key = snapshot.keyAt(StateEntryIndex(ordinal)).value
      let size = uint64(snapshot.lookup(key).value.byteLength)
      if size > uint64(limits.staging.valueBytes)-stagedValues:
        return refused[PreparedPagedState](PagedStateError.LimitExceeded)
      stagedValues += size
      bytes += size
    claims[index] = FullPagedRoot(root: committed.root, entries: uint64(committed.entries),
      nodes: committed.nodes, valueBytes: bytes)
  if stagedRecords > uint64(high(int) div sizeof(TrieRecord)):
    return refused[PreparedPagedState](PagedStateError.LengthOverflow)
  var records = newSeq[TrieRecord](int(stagedRecords))
  var next = 0
  for index in 0..history.len:
    # Exact-sized staging avoids unbounded growth and permits one bounded root export at a time.
    let snapshot = if index < history.len: history[index] else: source
    let claim = claims[index]
    let exported = snapshot.exportStateSnapshot(TrieExportLimits(records: TrieNodeLimit(
        claim.nodes),
      valueBytes: ByteLimit(claim.valueBytes)))
    if exported.error != TrieError.None:
      return PagedStateResult[PreparedPagedState](status: PagedStateError.ExportFailure,
          exportCause: exported.error)
    for record in exported.value.records:
      records[next] = record # Private export payloads become immutable before any prepared handle is published.
      inc next
  assert next == records.len
  records.sort(compareRecord)
  var unique = 0
  for index in 0..<records.len:
    # Duplicate complete addresses may collapse only after byte-for-byte physical field equality.
    if unique > 0 and array[32, byte](records[unique-1].digest) == array[32, byte](records[index].digest):
      if not sameRecord(records[unique-1], records[index]):
        return refused[PreparedPagedState](PagedStateError.RecordConflict)
    else:
      if unique != index:
        # Detach the record descriptor before mutating its source sequence under ARC loan checking.
        var copied = records[index]
        records[unique] = move(copied)
      inc unique
  records.setLen(unique)
  claims.sort(compareRoot)
  var roots: seq[FullPagedRoot] = @[]
  for claim in claims:
    # Equal logical roots must also agree in every recomputed complete-map total.
    if roots.len > 0 and array[32, byte](roots[^1].root) == array[32, byte](claim.root):
      let prior = roots[^1]
      if prior.entries != claim.entries or prior.nodes != claim.nodes or prior.valueBytes !=
          claim.valueBytes:
        return refused[PreparedPagedState](PagedStateError.RecordConflict)
    else:
      roots.add(claim)
  var payload = 0'u64
  for record in records:
    # Prove fixed framing plus raw values and aggregate payload before evaluating native wrapping arithmetic.
    let base = if record.kind == TrieRecordKind.Leaf: 72'u64 else: 97'u64
    let values = if record.kind == TrieRecordKind.Leaf: uint64(record.payload.len) else: 0'u64
    if values > high(uint64)-base: return refused[PreparedPagedState](
        PagedStateError.LengthOverflow)
    let size = base+values
    if size > high(uint64)-payload: return refused[PreparedPagedState](
        PagedStateError.LengthOverflow)
    payload += size
  let shape = pagedGeometry(uint64(records.len), payload, limits.dataset)
  if shape.error != PagedCodecError.None:
    return PagedStateResult[PreparedPagedState](status: PagedStateError.GeometryFailure,
        geometryCause: shape.error)
  PagedStateResult[PreparedPagedState](status: PagedStateError.None,
    completed: PreparedPagedState(data: PreparedData(root: source.commitment.root, roots: roots,
      records: records, payload: payload, fileBytes: shape.value.byteLength)))
proc producer*(prepared: PreparedPagedState): FullPagedProducer {.requires: prepared.data != nil.} =
  ## An owned immutable transport can safely outlive source maps and be replayed for explicit native cleanup.
  let data = prepared.data
  assert data != nil # Preserve the guarded owner proof for the local alias.
  proc next(pass: int, ordinal: uint64, output: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Mutable producer outputs are detached; an external caller cannot mutate private prepared backing storage.
    assert data != nil # This owned callback retains the immutable prepared backing.
    if ordinal >= uint64(data.records.len): return FullPagedProducerStep.End
    let stored = data.records[int(ordinal)]
    output = stored
    output.payload = newSeq[byte](stored.payload.len)
    for index in 0..<stored.payload.len: output.payload[index] = stored.payload[index] # Owned output bytes only.
    FullPagedProducerStep.Item
  next
proc initializePagedStateStore*(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig, prepared: PreparedPagedState, context: openArray[byte] = [
        ]): PagedStateResult[FullPagedPublication] =
  ## The caller retains the native close obligation, including acquired failed bootstrap owners and retirement diagnostics.
  let data = prepared.data
  if data == nil: return refused[FullPagedPublication](PagedStateError.Uninitialized)
  if array[32, byte](config.root) != array[32, byte](data.root):
    return refused[FullPagedPublication](PagedStateError.RootMismatch)
  let initialized = initializeFullPagedWriter(writer, path, config, data.roots,
    prepared.producer, uint64(data.records.len), data.payload, context)
  if initialized.error != FullPagedNativeError.None:
    return nativeFailed[FullPagedPublication, FullPagedPublication](initialized)
  PagedStateResult[FullPagedPublication](status: PagedStateError.None, completed: initialized.value)
proc preparePagedStateReplacement*(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    expected: FullPagedManifest, prepared: PreparedPagedState, context: openArray[byte] = [
        ]): PagedStateResult[StorageDurability] =
  ## Full snapshots publish only over the exact independently expected source; caller adopts memory only after confirmed native publish.
  let data = prepared.data
  if data == nil: return refused[StorageDurability](PagedStateError.Uninitialized)
  if not expected.initialized: return refused[StorageDurability](PagedStateError.StaleView)
  let selected = writer.selected
  if selected.error != FullPagedNativeError.None: return nativeFailed[StorageDurability,
      FullPagedManifest](selected)
  let a = expected.bytes
  let b = selected.value.bytes
  if a.error != FullPagedError.None:
    return PagedStateResult[StorageDurability](status: PagedStateError.CodecFailure,
        codecCause: a.error)
  if b.error != FullPagedError.None:
    return PagedStateResult[StorageDurability](status: PagedStateError.CodecFailure,
        codecCause: b.error)
  if a.value != b.value: return refused[StorageDurability](PagedStateError.StaleView)
  let preparedNative = prepareFullPagedReplacement(writer, candidate, data.root, data.roots,
    prepared.producer, uint64(data.records.len), data.payload, context)
  if preparedNative.error != FullPagedNativeError.None:
    return nativeFailed[StorageDurability, StorageDurability](preparedNative)
  PagedStateResult[StorageDurability](status: PagedStateError.None, completed: preparedNative.value)
proc restoreVisitor(stage: RestoreStage): FullPagedEntryVisitor =
  ## Copy only within independently selected complete-map ceilings; callback state never becomes a published store.
  proc visit(ordinal: uint64, key: StateKey, value: openArray[byte]): bool {.closure.} =
    ## Unexpected delivery shape and retained-value limits refuse before indexing or copying output.
    if ordinal != uint64(stage.next) or stage.next >= stage.entries.len:
      stage.reason = StateStoreError.InvalidRange
      return false
    let size = uint64(value.len)
    if size > uint64(stage.limits.trie.perValue) or size > uint64(
        stage.limits.trie.totalValueBytes)-stage.bytes:
      stage.reason = StateStoreError.LimitExceeded
      return false
    var owned = newSeq[byte](value.len)
    for index in 0..<value.len: owned[index] = value[index] # Copy before the borrowed native value expires.
    stage.entries[stage.next] = StateEntry(key: key, value: owned)
    inc stage.next
    stage.bytes += size
    true
  visit
proc restoreStage(claim: FullPagedRoot, limits: StateStoreLimits): PagedStateResult[RestoreStage] =
  ## Native complete-root claims preflight bounded private staging before any value callback or allocation.
  if claim.entries > uint64(limits.trie.items) or claim.nodes > uint64(limits.trie.nodes) or
      claim.valueBytes > uint64(limits.trie.totalValueBytes):
    return refused[RestoreStage](PagedStateError.LimitExceeded)
  if claim.entries > uint64(high(int) div sizeof(StateEntry)):
    return refused[RestoreStage](PagedStateError.LengthOverflow)
  PagedStateResult[RestoreStage](status: PagedStateError.None,
    completed: RestoreStage(entries: newSeq[StateEntry](int(claim.entries)), limits: limits,
      reason: StateStoreError.None))
proc finishRestore(stage: RestoreStage, expected: StateRoot, limits: StateStoreLimits,
    streamed: FullPagedNativeResult[FullPagedCounts]): PagedStateResult[StateStore] =
  ## A complete successful traversal and independently recomputed full-map root precede publication of any ordinary store.
  if streamed.error != FullPagedNativeError.None:
    if stage.reason != StateStoreError.None:
      return PagedStateResult[StateStore](status: PagedStateError.StateFailure,
          stateCause: stage.reason)
    return nativeFailed[StateStore, FullPagedCounts](streamed)
  if stage.next != stage.entries.len: return refused[StateStore](PagedStateError.RootMismatch)
  let restored = newStateStore(stage.entries, limits)
  if restored.error != StateStoreError.None:
    return PagedStateResult[StateStore](status: PagedStateError.StateFailure,
        stateCause: restored.error)
  if array[32, byte](restored.value.snapshot.value.commitment.root) != array[32, byte](expected):
    return refused[StateStore](PagedStateError.RootMismatch)
  PagedStateResult[StateStore](status: PagedStateError.None, completed: restored.value)

proc restorePagedStateStore*(reader: FullPagedReader, expected: StateRoot,
    limits: StateStoreLimits): PagedStateResult[StateStore] =
  ## An immutable reader reconstructs only its independently selected fully admitted complete root.
  let info = reader.rootInfo(expected)
  if info.error != FullPagedNativeError.None: return nativeFailed[StateStore, FullPagedRoot](info)
  let staged = restoreStage(info.value, limits)
  if staged.error != PagedStateError.None: return refused[StateStore](staged.error)
  let stage = staged.value
  finishRestore(stage, expected, limits, reader.visitEntries(expected, restoreVisitor(stage)))

proc restorePagedStateStore*(reader: FullPagedWriter, expected: StateRoot,
    limits: StateStoreLimits): PagedStateResult[StateStore] =
  ## Local startup reconstructs a complete map under its existing exclusive writer lease before context adoption.
  let info = reader.rootInfo(expected)
  if info.error != FullPagedNativeError.None: return nativeFailed[StateStore, FullPagedRoot](info)
  let staged = restoreStage(info.value, limits)
  if staged.error != PagedStateError.None: return refused[StateStore](staged.error)
  let stage = staged.value
  finishRestore(stage, expected, limits, reader.visitEntries(expected, restoreVisitor(stage)))
