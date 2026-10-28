# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Startup/excluded-worker historical staging binds immutable complete records to canonical publication plans.
## No helper selects a canonical state; callers confirm ordinary disk publication before installing cached selection or pruning.
import ./[chain, disk_history, historical_context, historical_record]
import ../chain/[genesis, provider]
import ../state/[store, disk_store]
import ../storage/[history_index, history_files, database_identity, node_repository, file_errors]
import ../codec/bounded

const DefaultHistoricalRecordBytes* = ByteLimit(16*1024*1024) ## Per-record working-set ceiling; archive length has no resident count ceiling.
type
  PreparedHistoricalRecord* = object ## Passive exact append and source snapshot travel with the existing exclusive IO-owner lease.
    ready: bool
    append: HistoryAppend
    saved: BlockSnapshotResult
  PreparedHistoryConfiguration* = object ## Fully staged configuration still requires one exact canonical context commit.
    ready, changed, reseeded: bool
    context: seq[byte]
    owner: ApplicationChain # The new bounded live state window preserves an independent header-only validation suffix.
    selection: CheckedHistorySelection
    cleanupFrom: HistoryCursor
    generation: RepositoryGeneration

func ready*(record: PreparedHistoricalRecord): bool =
  ## False means historical indexing is disabled for a legacy/default inline window.
  record.ready
func nextCursor*(record: PreparedHistoricalRecord): HistoryCursor {.requires: record.ready.} =
  ## Copied scalar metadata is eligible for publication only after complete record staging succeeds.
  record.append.nextCursor
func ready*(configuration: PreparedHistoryConfiguration): bool =
  ## Defaults never authorize context mutation, cache installation or pruning.
  configuration.ready
func changed*(configuration: PreparedHistoryConfiguration): bool {.requires: configuration.ready.} =
  ## An unchanged persisted policy needs only validated metadata and no new repository generation.
  configuration.changed
func reseeded*(configuration: PreparedHistoryConfiguration): bool {.requires: configuration.ready.} =
  ## Legacy inline migration stages a fresh local ordinal inventory and resets only obsolete cleanup progress.
  configuration.reseeded
proc context*(configuration: PreparedHistoryConfiguration): seq[
    byte] {.requires: configuration.ready and configuration.changed.} =
  ## Copy the exact bounded successor context after all encoding/staging checks.
  configuration.context
proc configuredOwner*(configuration: PreparedHistoryConfiguration): ApplicationChain {.requires: configuration.ready.} =
  ## Replace the canonical live view only after the corresponding context is confirmed durable.
  configuration.owner
func generation*(configuration: PreparedHistoryConfiguration): RepositoryGeneration {.requires: configuration.ready.} =
  ## A policy change advances ordinary durability independently of historical acceptance ordinals.
  configuration.generation
func selection*(configuration: PreparedHistoryConfiguration): CheckedHistorySelection {.requires: configuration.ready.} =
  ## Passive checked metadata owns no record list or native reader descriptor.
  configuration.selection
func cleanupFrom*(configuration: PreparedHistoryConfiguration): HistoryCursor {.requires: configuration.ready.} =
  ## Retire only the known predecessor/staged prefix after the new cursor is confirmed.
  configuration.cleanupFrom
proc historyNamespace*(disk: DiskStateStore): HistoryResult[string] =
  ## Keep archives under a deterministic sibling path while preserving the primary database writer's lease.
  if not disk.opened: return historyFailure[string](HistoryError.Uninitialized)
  let path = disk.databasePath
  if path.len == 0 or path.len > high(int)-16: return historyFailure[string](
      HistoryError.LimitExceeded)
  historySuccess(path & ".history")
proc checkedDiskHistory*(disk: var DiskStateStore, owner: ApplicationChain,
    chain: StorageChainId, limit: ByteLimit,
    recordBytes = DefaultHistoricalRecordBytes): HistoryResult[CheckedHistorySelection] =
  ## Startup validates the selected fixed-row suffix once; ordinary operations reuse only exact matching cached metadata.
  let current = disk.snapshot
  let canonical = owner.stateSnapshot
  if current.error != DiskStoreError.None or canonical.error != StateStoreError.None or
      not sameStateSnapshot(current.value, canonical.value):
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  if owner.chainView.hasHistoricalIndex:
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  let bytes = disk.snapshotContext
  if bytes.error != FileError.None: return historyFailure[CheckedHistorySelection](
      HistoryError.IoFailure)
  let generation = disk.generation
  if generation.error != DiskStoreError.None:
    return historyFailure[CheckedHistorySelection](HistoryError.IoFailure)
  let authority = encodeMatchingDiskHistory(owner, chain, generation.value, limit, bytes.value)
  if authority.error != DiskHistoryError.None or authority.value != bytes.value:
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  if not hasHistoricalContext(bytes.value): return historyFailure[CheckedHistorySelection](
      HistoryError.Unavailable)
  let context = decodeHistoricalContext(bytes.value, chain, limit)
  if context.error != HistoryError.None: return historyFailure[CheckedHistorySelection](context.error)
  let cursor = context.value.historicalCursor
  let selectedHead = owner.chainView.bestBlock
  if selectedHead.error != GenesisError.None or
      array[32, byte](selectedHead.value.blockHash) != array[32, byte](cursor.selectedHash) or
      selectedHead.value.slot != cursor.selectedSlot:
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  let cached = disk.checkedHistorySelection
  if cached.initialized and sameHistoryCursor(cached.historyCursor, cursor): return historySuccess(cached)
  let path = disk.historyNamespace
  if path.error != HistoryError.None: return historyFailure[CheckedHistorySelection](path.error)
  let files = openHistoryFiles(path.value, chain)
  if files.error != HistoryError.None: return historyFailure[CheckedHistorySelection](files.error)
  let selected = validateHistorySelection(files.value, cursor, recordBytes)
  if selected.error != HistoryError.None: return selected
  let row = selected.value.rowAt(cursor.lastOrdinal)
  if row.error != HistoryError.None: return historyFailure[CheckedHistorySelection](row.error)
  let head = owner.chainView.bestBlock
  if head.error != GenesisError.None or
      array[32, byte](head.value.blockHash) != array[32, byte](row.value.blockHash) or
      array[32, byte](head.value.stateRoot) != array[32, byte](row.value.stateRoot) or
      head.value.hasBlockBody != row.value.hasBody:
    return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
  if head.value.hasBlockBody and head.value.blockBodyDigest != array[32, byte](
      row.value.bodyDigest):
    return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
  disk.recordHistorySelection(selected.value)
  historySuccess(selected.value)
proc prepareHistoricalRecord*(previous: openArray[byte], saved: BlockSnapshotResult,
    chain: StorageChainId, limit: ByteLimit): HistoryResult[PreparedHistoricalRecord] =
  ## Host preflight computes only fixed metadata; checkpoint encoding and file IO belong to the excluded worker.
  if not hasHistoricalContext(previous): return historySuccess(default(PreparedHistoricalRecord))
  let context = decodeHistoricalContext(previous, chain, limit)
  if context.error != HistoryError.None: return historyFailure[PreparedHistoricalRecord](context.error)
  let append = prepareSnapshotHistory(context.value.historicalCursor, saved)
  if append.error != HistoryError.None: return historyFailure[PreparedHistoricalRecord](append.error)
  historySuccess(PreparedHistoricalRecord(ready: true, append: append.value, saved: saved))
proc stagePreparedHistory*(disk: DiskStateStore, record: PreparedHistoricalRecord,
    recordBytes = DefaultHistoricalRecordBytes): HistoryResult[CheckedHistorySelection] =
  ## Sync immutable record/index files before any ordinary canonical publication can reference the successor.
  if not record.ready: return historySuccess(default(CheckedHistorySelection))
  let bytes = disk.snapshotContext
  if bytes.error != FileError.None: return historyFailure[CheckedHistorySelection](
      HistoryError.IoFailure)
  let context = decodeHistoricalContext(bytes.value, record.append.previousCursor.chainId,
    disk.applicationContextLimit)
  if context.error != HistoryError.None: return historyFailure[CheckedHistorySelection](context.error)
  if not sameHistoryCursor(context.value.historicalCursor, record.append.previousCursor):
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  let path = disk.historyNamespace
  if path.error != HistoryError.None: return historyFailure[CheckedHistorySelection](path.error)
  let files = openHistoryFiles(path.value, record.append.nextCursor.chainId)
  if files.error != HistoryError.None: return historyFailure[CheckedHistorySelection](files.error)
  var before = disk.checkedHistorySelection
  if not before.initialized or not sameHistoryCursor(before.historyCursor,
      record.append.previousCursor):
    let checked = validateHistorySelection(files.value, record.append.previousCursor, recordBytes)
    if checked.error != HistoryError.None: return historyFailure[CheckedHistorySelection](checked.error)
    before = checked.value # This slow path admits lower-level opens once; normal publication retains constant cached metadata.
  let encoded = encodeHistoricalRecord(record.append, record.saved, recordBytes)
  if encoded.error != HistoryError.None: return historyFailure[CheckedHistorySelection](encoded.error)
  let staged = stageHistoryEntry(files.value, record.append, encoded.value, recordBytes)
  if staged.error != HistoryError.None: return historyFailure[CheckedHistorySelection](staged.error)
  advanceCheckedHistorySelection(before, record.append, recordBytes)
proc completeHistorySelection*(disk: var DiskStateStore, before: HistoryCursor,
    selected: CheckedHistorySelection, resetProgress = false): HistoryError =
  ## Confirm selection first; cleanup errors remain visible diagnostics and never revoke an accepted canonical successor.
  if not selected.initialized: return HistoryError.None
  let bytes = disk.snapshotContext
  var reason = HistoryError.None
  if bytes.error != FileError.None:
    reason = HistoryError.IoFailure
  else:
    let context = decodeHistoricalContext(bytes.value, selected.historyCursor.chainId,
        disk.applicationContextLimit)
    if context.error != HistoryError.None or not sameHistoryCursor(context.value.historicalCursor,
        selected.historyCursor):
      reason = HistoryError.StaleSelection
    else:
      disk.recordHistorySelection(selected) # Only an exact confirmed context may install the checked successor cache.
      let path = disk.historyNamespace
      if path.error != HistoryError.None:
        reason = path.error
      else:
        let files = openHistoryFiles(path.value, selected.historyCursor.chainId)
        if files.error != HistoryError.None:
          reason = files.error
        else:
          let pruned = pruneHistoryFiles(files.value, before, selected.historyCursor, resetProgress)
          if pruned.error != HistoryError.None: reason = pruned.error
  disk.recordHistoryCleanup(reason)
  reason
proc completePreparedHistory*(disk: var DiskStateStore, record: PreparedHistoricalRecord,
    selected: CheckedHistorySelection): HistoryError =
  ## Disabled inline history has no sibling namespace or cleanup work.
  if not record.ready: return HistoryError.None
  completeHistorySelection(disk, record.append.previousCursor, selected)
proc prepareHistoryConfiguration*(disk: var DiskStateStore, owner: ApplicationChain,
    chain: StorageChainId, policy: HistoryPolicy, previous: openArray[byte],
    generation: RepositoryGeneration, limit: ByteLimit,
    recordBytes = DefaultHistoricalRecordBytes): HistoryResult[PreparedHistoryConfiguration] =
  ## Startup-only two-pass staging preflights final context before writing any complete historical records.
  if not policy.initialized: return historyFailure[PreparedHistoryConfiguration](
      HistoryError.InvalidPolicy)
  if owner.chainView.hasHistoricalIndex:
    return historyFailure[PreparedHistoryConfiguration](
        HistoryError.StaleSelection) # Memory history cannot silently become a disk archive with an incomplete seed.
  let capacity = if policy.archive or policy.retainedBlocks > uint64(MaxRetainedBlocks):
    uint64(MaxRetainedBlocks) else: policy.retainedBlocks
  let limited = owner.chainView.withRetentionLimit(ElementLimit(capacity))
  if limited.error != ViewAdvanceError.None:
    return historyFailure[PreparedHistoryConfiguration](HistoryError.InvalidPolicy)
  let canonical = initApplicationChain(limited.value)
  if canonical.error != ApplicationChainError.None:
    return historyFailure[PreparedHistoryConfiguration](HistoryError.StaleSelection)
  var cursor = default(HistoryCursor)
  var checked = default(CheckedHistorySelection)
  var cleanup = default(HistoryCursor)
  let indexed = hasHistoricalContext(previous)
  if indexed:
    let selected = checkedDiskHistory(disk, owner, chain, limit, recordBytes)
    if selected.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](selected.error)
    checked = selected.value
    cleanup = checked.historyCursor
    let configured = cleanup.withHistoryPolicy(policy)
    if configured.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](
        configured.error)
    cursor = configured.value
    if sameHistoryCursor(cursor, cleanup) and sameChainView(owner.chainView,
        canonical.value.chainView):
      return historySuccess(PreparedHistoryConfiguration(ready: true, owner: owner,
        selection: checked,
        cleanupFrom: cleanup, generation: generation)) # Reopening with the stored policy does not consume a generation.
  else:
    let initial = initHistoryCursor(chain, policy)
    if initial.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](initial.error)
    cursor = initial.value
    for index in 0..<owner.chainView.retainedCount:
      let append = prepareSnapshotHistory(cursor, owner.chainView.retainedBlockAt(
          RetainedBlockIndex(index)))
      if append.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](append.error)
      cursor = append.value.nextCursor # First pass computes fixed scalar selection without retaining a seed-sized owner array.
  if uint64(generation) == high(uint64): return historyFailure[PreparedHistoryConfiguration](
      HistoryError.CounterExhausted)
  if uint64(limit) <= uint64(HistoricalContextPrefixBytes):
    return historyFailure[PreparedHistoryConfiguration](HistoryError.LimitExceeded)
  let nextGeneration = RepositoryGeneration(uint64(generation)+1)
  let live = encodeDiskHistory(canonical.value, chain, nextGeneration,
    ByteLimit(uint64(limit)-uint64(HistoricalContextPrefixBytes)))
  if live.error != DiskHistoryError.None: return historyFailure[PreparedHistoryConfiguration](
      HistoryError.LimitExceeded)
  let context = encodeHistoricalContext(cursor, live.value, limit)
  if context.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](context.error)
  if indexed:
    let changed = reselectCheckedHistory(checked, cursor)
    if changed.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](changed.error)
    checked = changed.value
  else:
    let path = disk.historyNamespace
    if path.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](path.error)
    let files = openHistoryFiles(path.value, chain, true)
    if files.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](files.error)
    var seed = initHistoryCursor(chain, policy).value
    let empty = validateHistorySelection(files.value, seed, recordBytes)
    if empty.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](empty.error)
    checked = empty.value
    for index in 0..<owner.chainView.retainedCount:
      let saved = owner.chainView.retainedBlockAt(RetainedBlockIndex(index))
      let append = prepareSnapshotHistory(seed, saved)
      if append.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](append.error)
      let encoded = encodeHistoricalRecord(append.value, saved, recordBytes)
      if encoded.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](encoded.error)
      let staged = stageHistoryEntry(files.value, append.value, encoded.value, recordBytes)
      if staged.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](staged.error)
      let admitted = advanceCheckedHistorySelection(checked, append.value, recordBytes)
      if admitted.error != HistoryError.None: return historyFailure[PreparedHistoryConfiguration](admitted.error)
      checked = admitted.value
      seed = staged.value
      if index == 0: cleanup = seed # A fresh seed may stage an older prefix that bounded retention immediately excludes.
    if not sameHistoryCursor(cursor, checked.historyCursor):
      return historyFailure[PreparedHistoryConfiguration](HistoryError.StaleSelection)
  historySuccess(PreparedHistoryConfiguration(ready: true, changed: true, reseeded: not indexed,
    context: context.value, owner: canonical.value, selection: checked, cleanupFrom: cleanup,
    generation: nextGeneration))

proc readDiskHistoricalSnapshot*(disk: var DiskStateStore, owner: ApplicationChain,
    chain: StorageChainId, hash: BlockHash, policy: StateStoreLimits, limit: ByteLimit,
    recordBytes = DefaultHistoricalRecordBytes): HistoryResult[ApplicationChain] =
  ## Full historical queries require exact current authority; selected finality remains available outside the user window.
  let selected = checkedDiskHistory(disk, owner, chain, limit, recordBytes)
  if selected.error != HistoryError.None and selected.error != HistoryError.Unavailable:
    return historyFailure[ApplicationChain](selected.error)
  let current = owner.stateSnapshot
  let requested = newStateStore([], policy)
  if current.error != StateStoreError.None or requested.error != StateStoreError.None or
      not sameStateStorePolicy(current.value, requested.value.snapshot.value):
    return historyFailure[ApplicationChain](HistoryError.InvalidPolicy)
  let finalized = owner.chainView.finalizedBlock
  if finalized.error == GenesisError.None and array[32, byte](hash) == array[32, byte](
      finalized.value.blockHash):
    let retained = initApplicationChain(genesisView(finalized))
    if retained.error != ApplicationChainError.None: return historyFailure[ApplicationChain](
        HistoryError.InvalidFormat)
    return historySuccess(retained.value)
  if selected.error == HistoryError.Unavailable:
    let saved = owner.chainView.blockAt(hash)
    if saved.error != GenesisError.None: return historyFailure[ApplicationChain](
        HistoryError.Unavailable)
    let retained = initApplicationChain(genesisView(saved))
    if retained.error != ApplicationChainError.None: return historyFailure[ApplicationChain](
        HistoryError.InvalidFormat)
    return historySuccess(retained.value) # Legacy/default databases expose only the supported inline window and explicit anchor.
  readHistoricalSnapshot(selected.value, HistoryBlockHash(array[32, byte](hash)),
    owner.chainView.bestBlock.value.chainParameters, policy, recordBytes)
proc readDiskHistoricalSnapshot*(disk: var DiskStateStore, owner: ApplicationChain,
    chain: StorageChainId, ordinal: HistoryOrdinal, policy: StateStoreLimits, limit: ByteLimit,
    recordBytes = DefaultHistoricalRecordBytes): HistoryResult[ApplicationChain] =
  ## Ordinals belong only to an indexed local history; old databases never infer a global height or genesis fallback.
  let selected = checkedDiskHistory(disk, owner, chain, limit, recordBytes)
  if selected.error != HistoryError.None: return historyFailure[ApplicationChain](selected.error)
  let current = owner.stateSnapshot
  let requested = newStateStore([], policy)
  if current.error != StateStoreError.None or requested.error != StateStoreError.None or
      not sameStateStorePolicy(current.value, requested.value.snapshot.value):
    return historyFailure[ApplicationChain](HistoryError.InvalidPolicy)
  readHistoricalSnapshot(selected.value, ordinal,
    owner.chainView.bestBlock.value.chainParameters, policy, recordBytes)
