# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Self-contained historical records bind an index row to exact block bytes and independently checked complete state.
## Each read owns one bounded record/map, never an archive-sized resident history list or partial light state.
import ./[chain, disk_head]
import ../chain/[genesis, provider, parameters]
import ../state/[store, checkpoint]
import ../storage/[history_index, history_files, node_repository]
import ../codec/bounded

const
  RecordMagic = "RAGNAROK-FULL-HISTORY-RECORD-V1\n"
  HistoricalRecordPrefixBytes* = 32+HistoryRowBytes+16 ## Row plus E8 local-head/checkpoint extents precede exact payloads.

func putNumber(bytes: var openArray[byte], offset: int, value: uint64) =
  ## Fixed callers prove the full E8 destination before bounded narrowing and shifts.
  for index in 0..<8: bytes[offset+index] = byte((value shr (index*8)) and 255)
func number(bytes: openArray[byte], offset: int): uint64 =
  ## Fixed callers prove a complete E8 field before reading it.
  result = 0
  for index in 0..<8: result = result or (uint64(bytes[offset+index]) shl (index*8))
proc matches(snapshot: BlockSnapshot, row: HistoryRow): bool =
  ## Exact identity checks do not allocate body-sized buffers or substitute a detached state map.
  if array[32, byte](snapshot.blockHash) != array[32, byte](row.blockHash) or
      array[32, byte](snapshot.parentHash) != array[32, byte](row.parentHash) or
      array[32, byte](snapshot.stateRoot) != array[32, byte](row.stateRoot) or
      snapshot.slot != row.slot or snapshot.hasBlockBody != row.hasBody:
    return false
  not row.hasBody or snapshot.blockBodyDigest == array[32, byte](row.bodyDigest)
proc prepareSnapshotHistory*(cursor: HistoryCursor,
    saved: BlockSnapshotResult): HistoryResult[HistoryAppend] =
  ## Bind only a completely captured snapshot; live callers pass their genuine privately prepared child.
  if saved.error != GenesisError.None: return historyFailure[HistoryAppend](
      HistoryError.InvalidFormat)
  let snapshot = saved.value
  let body = if snapshot.hasBlockBody: HistoryDigest(snapshot.blockBodyDigest) else: default(HistoryDigest)
  prepareHistoryAppend(cursor, HistoryBlockHash(array[32, byte](snapshot.blockHash)),
    HistoryBlockHash(array[32, byte](snapshot.parentHash)), snapshot.stateRoot, snapshot.slot,
    snapshot.hasBlockBody, body)
proc encodeHistoricalRecord*(append: HistoryAppend, saved: BlockSnapshotResult,
    limit: ByteLimit): HistoryResult[seq[byte]] =
  ## Fully encode before IO; the existing canonical checkpoint encoding supplies complete-state bytes.
  if not append.ready: return historyFailure[seq[byte]](HistoryError.Uninitialized)
  if saved.error != GenesisError.None or not matches(saved.value, append.indexRow):
    return historyFailure[seq[byte]](HistoryError.InvalidFormat)
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < uint64(HistoricalRecordPrefixBytes): return historyFailure[seq[byte]](
      HistoryError.LimitExceeded)
  let owner = initApplicationChain(genesisView(saved))
  if owner.error != ApplicationChainError.None: return historyFailure[seq[byte]](
      HistoryError.InvalidFormat)
  let head = encodeDiskHead(owner.value, append.nextCursor.chainId,
    RepositoryGeneration(uint64(append.indexRow.ordinal)), limit)
  if head.error != DiskHeadError.None: return historyFailure[seq[byte]](HistoryError.LimitExceeded)
  let state = encodeFullCheckpoint(saved.value.stateSnapshot, limit)
  if state.error != CheckpointError.None: return historyFailure[seq[byte]](
      HistoryError.LimitExceeded)
  let headBytes = head.value
  let stateBytes = state.value
  let available = maximum-uint64(HistoricalRecordPrefixBytes)
  if uint64(headBytes.len) > available or uint64(stateBytes.len) > available-uint64(
      headBytes.len):
    return historyFailure[seq[byte]](HistoryError.LimitExceeded)
  let index = encodeHistoryRow(append.indexRow)
  if index.error != HistoryError.None: return historyFailure[seq[byte]](index.error)
  var bytes = newSeq[byte](HistoricalRecordPrefixBytes+headBytes.len+stateBytes.len)
  for position, character in RecordMagic: bytes[position] = byte(character)
  for position, octet in index.value: bytes[32+position] = octet
  putNumber(bytes, 32+HistoryRowBytes, uint64(headBytes.len))
  putNumber(bytes, 40+HistoryRowBytes, uint64(stateBytes.len))
  for position, octet in headBytes: bytes[HistoricalRecordPrefixBytes+position] = octet
  for position, octet in stateBytes: bytes[HistoricalRecordPrefixBytes+headBytes.len+position] = octet
  historySuccess(bytes)
proc decodeHistoricalRecord*(bytes: openArray[byte], expected: HistoryRow,
    cursor: HistoryCursor, parameters: Parameters, policy: StateStoreLimits,
    limit: ByteLimit): HistoryResult[ApplicationChain] =
  ## Extents and exact index identity precede state allocation; complete root and body identity precede success.
  if not expected.initialized or not cursor.initialized:
    return historyFailure[ApplicationChain](HistoryError.Uninitialized)
  if uint64(bytes.len) > uint64(limit): return historyFailure[ApplicationChain](
      HistoryError.LimitExceeded)
  if bytes.len <= HistoricalRecordPrefixBytes: return historyFailure[ApplicationChain](
      HistoryError.InvalidFormat)
  for position in 0..<32:
    let wanted = if position < RecordMagic.len: byte(RecordMagic[position]) else: 0'u8
    if bytes[position] != wanted: return historyFailure[ApplicationChain](
        HistoryError.InvalidFormat)
  let row = decodeHistoryRow(bytes.toOpenArray(32, 32+HistoryRowBytes-1))
  if row.error != HistoryError.None: return historyFailure[ApplicationChain](row.error)
  if array[32, byte](row.value.rowDigest) != array[32, byte](expected.rowDigest):
    return historyFailure[ApplicationChain](HistoryError.ChecksumMismatch)
  let headLength = number(bytes, 32+HistoryRowBytes)
  let stateLength = number(bytes, 40+HistoryRowBytes)
  let remaining = uint64(bytes.len-HistoricalRecordPrefixBytes)
  if headLength == 0 or headLength > remaining or stateLength == 0 or stateLength !=
      remaining-headLength:
    return historyFailure[ApplicationChain](HistoryError.InvalidFormat)
  let headEnd = HistoricalRecordPrefixBytes+int(headLength) # Input bounds prove host conversion and addition.
  let state = decodeFullCheckpoint(bytes.toOpenArray(headEnd, bytes.high), expected.stateRoot,
      policy, limit)
  if state.error != CheckpointError.None: return historyFailure[ApplicationChain](
      HistoryError.ChecksumMismatch)
  let snapshot = state.value.snapshot
  if snapshot.error != StateStoreError.None: return historyFailure[ApplicationChain](
      HistoryError.InvalidFormat)
  let head = restoreDiskHead(bytes.toOpenArray(HistoricalRecordPrefixBytes, headEnd-1),
      cursor.chainId,
    RepositoryGeneration(uint64(expected.ordinal)), parameters, snapshot.value, limit)
  if head.error != DiskHeadError.None: return historyFailure[ApplicationChain](
      HistoryError.InvalidFormat)
  if not matches(head.value.chainView.bestBlock.value, expected):
    return historyFailure[ApplicationChain](HistoryError.ChecksumMismatch)
  historySuccess(head.value)
proc readHistoricalSnapshot*(selection: CheckedHistorySelection, ordinal: HistoryOrdinal,
    parameters: Parameters, policy: StateStoreLimits, limit: ByteLimit): HistoryResult[
        ApplicationChain] =
  ## One ordinal lookup loads only the requested complete record; returned immutable state/body owners survive pruning.
  let row = selection.rowAt(ordinal)
  if row.error != HistoryError.None: return historyFailure[ApplicationChain](row.error)
  let bytes = selection.readHistoryRecord(row.value, limit)
  if bytes.error != HistoryError.None: return historyFailure[ApplicationChain](bytes.error)
  decodeHistoricalRecord(bytes.value, row.value, selection.historyCursor, parameters, policy, limit)
proc readHistoricalSnapshot*(selection: CheckedHistorySelection, hash: HistoryBlockHash,
    parameters: Parameters, policy: StateStoreLimits, limit: ByteLimit): HistoryResult[
        ApplicationChain] =
  ## A hash alias must resolve the same selected ordinal row before the complete state is decoded.
  let row = selection.rowAt(hash)
  if row.error != HistoryError.None: return historyFailure[ApplicationChain](row.error)
  let bytes = selection.readHistoryRecord(row.value, limit)
  if bytes.error != HistoryError.None: return historyFailure[ApplicationChain](bytes.error)
  decodeHistoricalRecord(bytes.value, row.value, selection.historyCursor, parameters, policy, limit)
