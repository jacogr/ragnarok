# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real historical files preserve exact records, ignore unselected tails and reclaim only a confirmed retained suffix.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/disk_history_context
import ../../../src/app/[chain, historical_record]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/storage/[history_index, history_files, database_identity]
import ../../../src/lib/atomic_file
import ../../../src/codec/[bounded, header]

proc historyPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Failed assertion artifacts never collide with a later process-owned witness.
func hashName(hash: BlockHash): string =
  ## Test-owned filenames use all 256 header bits and no directory traversal bytes.
  const digits = "0123456789abcdef"
  let source = array[32, byte](hash)
  result = newString(64)
  for index, octet in source:
    result[index*2] = digits[int(octet shr 4)]
    result[index*2+1] = digits[int(octet and 15)]
proc cleanup(folder: string, blocks: openArray[BlockSnapshotResult]) =
  ## Remove only this test's exact ordinal/hash inventory; no production directory scan or broad deletion.
  for index, saved in blocks:
    var row = folder & "/row-" & $(uint64(index)+1)
    var record = folder & "/record-" & $(uint64(index)+1)
    var alias = folder & "/block-" & hashName(saved.value.blockHash)
    discard posix.unlink(row.toCString())
    discard posix.unlink(record.toCString())
    discard posix.unlink(alias.toCString())
  var progress = folder & "/CLEANUP"
  discard posix.unlink(progress.toCString())
  var identity = folder & "/identity"
  var path = folder
  discard posix.unlink(identity.toCString())
  assert posix.rmdir(path.toCString()) == 0
proc main() {.raises.} =
  ## Structural bodies exercise exact byte/storage contracts; genuine accepted execution is qualified by disk_chain.
  let fixture = diskHistoryFixture(16)
  var blocks = fixture.blocks
  for index in 1..<blocks.len:
    let snapshot = blocks[index].value
    var body = newSeq[byte](snapshot.header.headerInfo.value.consumed+7)
    assert encodeOwnedHeader(snapshot.header, body).error == HeaderError.None
    blocks[index] = withBlockBody(snapshot, body)
    assert blocks[index].error == GenesisError.None
  let chain = default(StorageChainId)
  let limit = ByteLimit(8388608)
  let folder = "historical-records-" & $historyPid()
  let files = openHistoryFiles(folder, chain, true).value
  defer: cleanup(folder, blocks)
  var cursor = initHistoryCursor(chain, archiveHistoryPolicy()).value
  for index in 0..<12:
    let prepared = prepareSnapshotHistory(cursor, blocks[index]).value
    let record = encodeHistoricalRecord(prepared, blocks[index], limit).value
    cursor = stageHistoryEntry(files, prepared, record, limit).value
  let selected = validateHistorySelection(files, cursor, limit).value
  assert selected.historyCursor.len == 12
  let parameters = blocks[0].value.chainParameters
  let held = readHistoricalSnapshot(selected, HistoryOrdinal(2), parameters, fixture.policy, limit).value
  assert held.chainView.bestBlock.value.hasBlockBody
  let heldBytes = held.chainView.bestBlock.value.blockBody
  assert heldBytes == blocks[1].value.blockBody
  assert not readHistoricalSnapshot(selected, HistoryOrdinal(1), parameters,
    fixture.policy, limit).value.chainView.bestBlock.value.hasBlockBody
  let byHash = readHistoricalSnapshot(selected, HistoryBlockHash(array[32, byte](blocks[
      1].value.blockHash)),
    parameters, fixture.policy, limit).value
  assert array[32, byte](byHash.stateSnapshot.value.commitment.root) == array[32, byte](blocks[
      1].value.stateRoot)
  # Staging all bytes alone does not publish a new selection or make an orphan hash queryable.
  let pending = prepareSnapshotHistory(cursor, blocks[12]).value
  let encoded = encodeHistoricalRecord(pending, blocks[12], limit).value
  assert stageHistoryEntry(files, pending, encoded, ByteLimit(encoded.len-1)).error ==
      HistoryError.LimitExceeded
  assert selected.rowAt(HistoryOrdinal(13)).error == HistoryError.Unavailable
  let future = stageHistoryEntry(files, pending, encoded, limit).value
  assert selected.rowAt(HistoryBlockHash(array[32, byte](blocks[12].value.blockHash))).error ==
      HistoryError.Unavailable
  let committed = validateHistorySelection(files, future, limit).value
  assert committed.historyCursor.len == 13 and selected.historyCursor.len == 12
  # Every truncation and an impossible extent refuse before a partial complete-map owner escapes.
  for stop in 0..<encoded.len:
    assert decodeHistoricalRecord(encoded.toOpenArray(0, stop-1), pending.indexRow,
      future, parameters, fixture.policy, limit).error != HistoryError.None
  var modified = encoded
  for position in HistoricalRecordPrefixBytes-16..<HistoricalRecordPrefixBytes-8: modified[position] = 255
  assert decodeHistoricalRecord(modified, pending.indexRow, future,
    parameters, fixture.policy, limit).error == HistoryError.InvalidFormat
  modified = encoded
  modified[modified.high] = modified[modified.high] xor 1
  assert decodeHistoricalRecord(modified, pending.indexRow, future,
    parameters, fixture.policy, limit).error == HistoryError.ChecksumMismatch
  # A deterministic staging IO failure leaves the previous committed cursor fully queryable.
  let failed = prepareSnapshotHistory(future, blocks[13]).value
  let nextRecord = encodeHistoricalRecord(failed, blocks[13], limit).value
  var blocked = folder & "/record-14"
  assert posix.mkdir(blocked.toCString(), Mode(0o700)) == 0
  assert stageHistoryEntry(files, failed, nextRecord, limit).error == HistoryError.IoFailure
  assert validateHistorySelection(files, future, limit).error == HistoryError.None
  assert posix.rmdir(blocked.toCString()) == 0
  let narrow = future.withHistoryPolicy(boundedHistoryPolicy(3).value).value
  assert uint64(narrow.firstOrdinal) == 11
  var interrupted = folder & "/record-5"
  assert posix.unlink(interrupted.toCString()) == 0
  assert posix.mkdir(interrupted.toCString(), Mode(0o700)) == 0
  assert pruneHistoryFiles(files, future, narrow).error == HistoryError.IoFailure
  assert validateHistorySelection(files, narrow, limit).error == HistoryError.None
  assert posix.rmdir(interrupted.toCString()) == 0
  assert pruneHistoryFiles(files, future, narrow).value ==
      10 # Retry skips already removed prefix files before acknowledging progress.
  assert pruneHistoryFiles(files, future, narrow).value ==
      0 # Durable acknowledgement avoids rescanning the reclaimed prefix.
  let reopened = openHistoryFiles(folder, chain).value
  let pruned = validateHistorySelection(reopened, narrow, limit).value
  assert pruned.rowAt(HistoryOrdinal(2)).error == HistoryError.Pruned
  assert pruned.rowAt(HistoryBlockHash(array[32, byte](blocks[1].value.blockHash))).error ==
      HistoryError.Unavailable
  assert held.chainView.bestBlock.value.blockBody == heldBytes
  assert array[32, byte](held.stateSnapshot.value.commitment.root) == array[32, byte](blocks[
      1].value.stateRoot)
  let archive = narrow.withHistoryPolicy(archiveHistoryPolicy()).value
  assert archive.len == 3 and uint64(archive.firstOrdinal) ==
      11 # Switching to archive cannot restore deleted records.
  assert validateHistorySelection(reopened, archive, limit).error == HistoryError.None
  var wrong = default(array[32, byte])
  wrong[0] = 1
  assert openHistoryFiles(folder, StorageChainId(wrong)).error == HistoryError.WrongChain
  # A changed retained row cannot be admitted even when the complete record still exists.
  var row = encodeHistoryRow(pending.indexRow).value
  row[208] = row[208] xor 1
  let lastPath = folder & "/row-13"
  assert replaceAtomicFile(lastPath, row, ByteLimit(HistoryRowBytes)) == AtomicFileError.None
  assert validateHistorySelection(files, narrow, limit).error == HistoryError.ChecksumMismatch
  let original = encodeHistoryRow(pending.indexRow).value
  assert replaceAtomicFile(lastPath, original, ByteLimit(HistoryRowBytes)) == AtomicFileError.None
  assert validateHistorySelection(files, narrow, limit).error == HistoryError.None

try:
  main()
except:
  quit(2) # IO, fixture and malformed-record failures never count as successful historical reads.
echo "PASS historical records: exact block/state reads, staged orphan exclusion, bounded lookup, pruning and retained readers"
