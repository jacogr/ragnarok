# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable per-ordinal records and hash/ordinal indexes stage before canonical cursor publication.
## The full-node database writer serializes callers and keeps this sibling namespace stable during IO.
## Checked selections retain constant metadata; completed record reads own their bytes across pruning.
import std/posix/posix
import ./index as history_index
import ../database_identity
import ../../lib/atomic/file as atomic_file
import ../../codec/bounded
import ../../crypto/primitives

const IdentityMagic = "RAGNAROK-FULL-HISTORY-V1\n"
type
  HistoryFiles* = object ## Passive namespace capability owns no native descriptor, callback or resident archive list.
    ready: bool
    folder: string
    chain: StorageChainId
  CheckedHistorySelection* = object ## Complete suffix admission retains only exact scalar selection and namespace identity.
    ready: bool
    files: HistoryFiles
    cursor: HistoryCursor

proc openDescriptor(path: cstring, flags: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## The SDK supplies the native two-argument non-creation ABI.

proc synchronize(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## Directory synchronization makes namespace changes explicitly durable.

func parent(path: string): string =
  ## Find a stable parent without normalizing or silently changing caller path identity.
  var slash = -1
  for index, character in path:
    if character == '/': slash = index
  if slash < 0: "." elif slash == 0: "/" else: path.substr(0, slash-1)

proc syncDirectory(path: string): HistoryError =
  ## One native directory owner is retired on every kind/sync/close path.
  var name = path
  let descriptor = openDescriptor(name.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK)
  if descriptor < 0: return HistoryError.IoFailure
  var metadata = default(Stat)
  let valid = posix.fstat(descriptor, metadata) == 0 and S_ISDIR(metadata.st_mode)
  let synced = valid and synchronize(descriptor) == 0
  let closed = posix.close(descriptor) == 0 # Interrupted close never retries a potentially reused descriptor.
  if synced and closed: HistoryError.None else: HistoryError.PublishedUnsynced

func fileReason(reason: AtomicFileError): HistoryError =
  ## Preserve visibility uncertainty and resource refusals independently of canonical selection.
  case reason
  of AtomicFileError.None: HistoryError.None
  of AtomicFileError.LimitExceeded: HistoryError.LimitExceeded
  of AtomicFileError.PublishedUnsynced: HistoryError.PublishedUnsynced
  else: HistoryError.IoFailure

proc absent(path: string): bool =
  ## Only ENOENT means unavailable; permission and invalid-parent failures remain real IO errors.
  var name = path
  var metadata = default(Stat)
  posix.stat(name.toCString(), metadata) != 0 and errno() == ENOENT

func ordinalPath(files: HistoryFiles, ordinal: HistoryOrdinal, record: bool): string =
  ## Namespace admission reserves enough path capacity for the longest E8 decimal suffix.
  files.folder & (if record: "/record-" else: "/row-") & $uint64(ordinal)

func hashPath(files: HistoryFiles, hash: HistoryBlockHash): string =
  ## Full 256-bit names never truncate identities or interpret raw bytes as paths.
  const digits = "0123456789abcdef"
  let source = array[32, byte](hash)
  var text = newString(64)
  for index, octet in source:
    text[index*2] = digits[int(octet shr 4)]
    text[index*2+1] = digits[int(octet and 15)]
  files.folder & "/block-" & text

func initialized*(files: HistoryFiles): bool =
  ## Defaults grant no namespace authority.
  files.ready

func initialized*(selection: CheckedHistorySelection): bool =
  ## A parsed cursor alone does not establish that every retained index row exists.
  selection.ready

func historyCursor*(selection: CheckedHistorySelection): HistoryCursor {.requires: selection.ready.} =
  ## Return copied scalar metadata, never an archive-sized table or mutable cache.
  selection.cursor

proc openHistoryFiles*(folder: string, chain: StorageChainId,
    create = false, exclusive = false): HistoryResult[HistoryFiles] =
  ## Validate a separate full-node chain identity; opening never adopts a different mode/schema or chain.
  if folder.len == 0 or folder.len > high(int)-128:
    return historyFailure[HistoryFiles](HistoryError.IoFailure)
  for character in folder:
    if character == char(0): return historyFailure[HistoryFiles](HistoryError.IoFailure)
  var name = folder
  if exclusive and not create: return historyFailure[HistoryFiles](HistoryError.InvalidFormat)
  if create and posix.mkdir(name.toCString(), Mode(0o700)) != 0:
    if errno() != EEXIST: return historyFailure[HistoryFiles](HistoryError.IoFailure)
    if exclusive: return historyFailure[HistoryFiles](
        HistoryError.AlreadyExists) # A migration never adopts or replaces an existing destination catalog.
  var metadata = default(Stat)
  if posix.stat(name.toCString(), metadata) != 0 or not S_ISDIR(metadata.st_mode):
    return historyFailure[HistoryFiles](HistoryError.IoFailure)
  let identityPath = folder & "/identity"
  var expected = default(array[64, byte])
  for index, character in IdentityMagic: expected[index] = byte(character)
  let id = array[32, byte](chain)
  for index in 0..<32: expected[32+index] = id[index]
  if create and absent(identityPath):
    let written = replaceAtomicFile(identityPath, expected, ByteLimit(64))
    if written != AtomicFileError.None: return historyFailure[HistoryFiles](fileReason(written))
    let synced = syncDirectory(parent(folder))
    if synced != HistoryError.None: return historyFailure[HistoryFiles](synced)
  let actual = readBoundedFile(identityPath, ByteLimit(64))
  if actual.error != AtomicFileError.None:
    return historyFailure[HistoryFiles](fileReason(actual.error))
  if actual.value.len != expected.len: return historyFailure[HistoryFiles](
      HistoryError.InvalidFormat)
  for index in 0..<32:
    if actual.value[index] != expected[index]: return historyFailure[HistoryFiles](
        HistoryError.InvalidFormat)
  for index in 32..<64:
    if actual.value[index] != expected[index]: return historyFailure[HistoryFiles](
        HistoryError.WrongChain)
  historySuccess(HistoryFiles(ready: true, folder: folder, chain: chain))

proc readRawRow(files: HistoryFiles, ordinal: HistoryOrdinal): HistoryResult[HistoryRow] =
  ## Missing retained rows are corruption/IO failure; callers test pruning bounds before this access.
  let read = readBoundedFile(ordinalPath(files, ordinal, false), ByteLimit(HistoryRowBytes))
  if read.error != AtomicFileError.None: return historyFailure[HistoryRow](fileReason(read.error))
  let decoded = decodeHistoryRow(read.value)
  if decoded.error != HistoryError.None: return decoded
  if uint64(decoded.value.ordinal) != uint64(ordinal): return historyFailure[HistoryRow](
      HistoryError.InvalidFormat)
  decoded

proc recordPresent(files: HistoryFiles, ordinal: HistoryOrdinal, limit: ByteLimit): HistoryError =
  ## Startup admits bounded regular records without loading every complete historical map into memory.
  var name = ordinalPath(files, ordinal, true)
  var metadata = default(Stat)
  if posix.stat(name.toCString(), metadata) != 0 or not S_ISREG(metadata.st_mode) or
      metadata.st_size <= 0:
    return HistoryError.IoFailure
  if uint64(metadata.st_size) > uint64(limit): return HistoryError.LimitExceeded
  HistoryError.None

proc validateHistorySelection*(files: HistoryFiles, cursor: HistoryCursor,
    recordBytes: ByteLimit): HistoryResult[CheckedHistorySelection] =
  ## Scan fixed rows with constant memory; the canonical terminal digest authenticates the retained suffix.
  if not files.ready or not cursor.initialized:
    return historyFailure[CheckedHistorySelection](HistoryError.Uninitialized)
  if array[32, byte](files.chain) != array[32, byte](cursor.chainId):
    return historyFailure[CheckedHistorySelection](HistoryError.WrongChain)
  if uint64(cursor.lastOrdinal) == 0:
    return historySuccess(CheckedHistorySelection(ready: true, files: files, cursor: cursor))
  var index = uint64(cursor.firstOrdinal)
  var previous = default(HistoryRow)
  while true:
    let read = readRawRow(files, HistoryOrdinal(index))
    if read.error != HistoryError.None: return historyFailure[CheckedHistorySelection](read.error)
    let row = read.value
    if previous.initialized:
      if array[32, byte](row.previousDigest) != array[32, byte](previous.rowDigest) or
          array[32, byte](row.parentHash) != array[32, byte](previous.blockHash):
        return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
      if row.slot <= previous.slot: return historyFailure[CheckedHistorySelection](
          HistoryError.SlotNotIncreasing)
    let alias = readBoundedFile(hashPath(files, row.blockHash), ByteLimit(HistoryRowBytes))
    if alias.error != AtomicFileError.None: return historyFailure[CheckedHistorySelection](
        fileReason(alias.error))
    let aliased = decodeHistoryRow(alias.value)
    if aliased.error != HistoryError.None or array[32, byte](aliased.value.rowDigest) != array[32,
        byte](row.rowDigest):
      return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
    let present = recordPresent(files, row.ordinal, recordBytes)
    if present != HistoryError.None: return historyFailure[CheckedHistorySelection](present)
    if index == uint64(cursor.lastOrdinal):
      if array[32, byte](row.rowDigest) != array[32, byte](cursor.selectedDigest) or
          array[32, byte](row.blockHash) != array[32, byte](cursor.selectedHash) or row.slot !=
              cursor.selectedSlot:
        return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
      break # Equality proves the loop never increments high(uint64).
    previous = row
    inc index
  historySuccess(CheckedHistorySelection(ready: true, files: files, cursor: cursor))

proc stageHistoryEntry*(files: HistoryFiles, append: HistoryAppend,
    record: openArray[byte], recordBytes: ByteLimit): HistoryResult[HistoryCursor] =
  ## Sync record, ordinal row and hash alias before returning a cursor eligible for canonical publication.
  ## Replacing an orphan future ordinal is safe; selected-prefix rows are never staging targets.
  if not files.ready or not append.ready: return historyFailure[HistoryCursor](
      HistoryError.Uninitialized)
  if array[32, byte](files.chain) != array[32, byte](append.nextCursor.chainId):
    return historyFailure[HistoryCursor](HistoryError.WrongChain)
  if record.len == 0: return historyFailure[HistoryCursor](HistoryError.InvalidFormat)
  if uint64(record.len) > uint64(recordBytes): return historyFailure[HistoryCursor](
      HistoryError.LimitExceeded)
  let row = append.indexRow
  let encoded = encodeHistoryRow(row)
  if encoded.error != HistoryError.None: return historyFailure[HistoryCursor](encoded.error)
  let payload = replaceAtomicFile(ordinalPath(files, row.ordinal, true), record, recordBytes)
  if payload != AtomicFileError.None: return historyFailure[HistoryCursor](fileReason(payload))
  let indexed = replaceAtomicFile(ordinalPath(files, row.ordinal, false), encoded.value, ByteLimit(HistoryRowBytes))
  if indexed != AtomicFileError.None: return historyFailure[HistoryCursor](fileReason(indexed))
  let alias = replaceAtomicFile(hashPath(files, row.blockHash), encoded.value, ByteLimit(HistoryRowBytes))
  if alias != AtomicFileError.None: return historyFailure[HistoryCursor](fileReason(alias))
  historySuccess(append.nextCursor)

proc advanceCheckedHistorySelection*(before: CheckedHistorySelection, append: HistoryAppend,
    recordBytes: ByteLimit): HistoryResult[CheckedHistorySelection] =
  ## An immutable already checked prefix plus one fully staged row admits a successor in constant metadata work.
  if not before.ready or not append.ready:
    return historyFailure[CheckedHistorySelection](HistoryError.Uninitialized)
  if not sameHistoryCursor(before.cursor, append.previousCursor):
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  let expected = append.indexRow
  let row = readRawRow(before.files, expected.ordinal)
  if row.error != HistoryError.None: return historyFailure[CheckedHistorySelection](row.error)
  if row.value.rowDigest != expected.rowDigest:
    return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
  let alias = readBoundedFile(hashPath(before.files, expected.blockHash), ByteLimit(HistoryRowBytes))
  if alias.error != AtomicFileError.None:
    return historyFailure[CheckedHistorySelection](fileReason(alias.error))
  let indexed = decodeHistoryRow(alias.value)
  if indexed.error != HistoryError.None or indexed.value.rowDigest != expected.rowDigest:
    return historyFailure[CheckedHistorySelection](HistoryError.ChecksumMismatch)
  let present = recordPresent(before.files, expected.ordinal, recordBytes)
  if present != HistoryError.None: return historyFailure[CheckedHistorySelection](present)
  historySuccess(CheckedHistorySelection(ready: true, files: before.files,
      cursor: append.nextCursor))

func reselectCheckedHistory*(before: CheckedHistorySelection,
    cursor: HistoryCursor): HistoryResult[CheckedHistorySelection] =
  ## An unchanged checked terminal row permits only policy changes that preserve or shrink the available suffix.
  if not before.ready or not cursor.initialized:
    return historyFailure[CheckedHistorySelection](HistoryError.Uninitialized)
  if array[32, byte](before.cursor.chainId) != array[32, byte](cursor.chainId) or
      before.cursor.lastOrdinal != cursor.lastOrdinal or
      cursor.firstOrdinal < before.cursor.firstOrdinal or
      before.cursor.selectedHash != cursor.selectedHash or
      before.cursor.selectedDigest != cursor.selectedDigest or before.cursor.selectedSlot !=
          cursor.selectedSlot:
    return historyFailure[CheckedHistorySelection](HistoryError.StaleSelection)
  historySuccess(CheckedHistorySelection(ready: true, files: before.files, cursor: cursor))

proc rowAt*(selection: CheckedHistorySelection, ordinal: HistoryOrdinal): HistoryResult[HistoryRow] =
  ## Indexed ordinal addressing does not scan or allocate an archive-sized container.
  if not selection.ready: return historyFailure[HistoryRow](HistoryError.Uninitialized)
  if uint64(ordinal) == 0 or uint64(ordinal) > uint64(selection.cursor.lastOrdinal):
    return historyFailure[HistoryRow](HistoryError.Unavailable)
  if uint64(ordinal) < uint64(selection.cursor.firstOrdinal): return historyFailure[HistoryRow](
      HistoryError.Pruned)
  readRawRow(selection.files, ordinal)

proc rowAt*(selection: CheckedHistorySelection, hash: HistoryBlockHash): HistoryResult[HistoryRow] =
  ## A stale orphan alias cannot select a future ordinal or substitute another selected row.
  if not selection.ready: return historyFailure[HistoryRow](HistoryError.Uninitialized)
  let path = hashPath(selection.files, hash)
  let alias = readBoundedFile(path, ByteLimit(HistoryRowBytes))
  if alias.error != AtomicFileError.None:
    if absent(path): return historyFailure[HistoryRow](HistoryError.Unavailable)
    return historyFailure[HistoryRow](fileReason(alias.error))
  let decoded = decodeHistoryRow(alias.value)
  if decoded.error != HistoryError.None: return decoded
  if array[32, byte](decoded.value.blockHash) != array[32, byte](hash):
    return historyFailure[HistoryRow](HistoryError.ChecksumMismatch)
  let selected = selection.rowAt(decoded.value.ordinal)
  if selected.error != HistoryError.None: return selected
  if array[32, byte](selected.value.rowDigest) != array[32, byte](decoded.value.rowDigest):
    return historyFailure[HistoryRow](HistoryError.Unavailable)
  selected

proc readHistoryRecord*(selection: CheckedHistorySelection, row: HistoryRow,
    recordBytes: ByteLimit): HistoryResult[seq[byte]] =
  ## Complete bounded reads close their descriptor before returning independent bytes, which survive unlink/pruning.
  if not selection.ready or not row.initialized: return historyFailure[seq[byte]](
      HistoryError.Uninitialized)
  let selected = selection.rowAt(row.ordinal)
  if selected.error != HistoryError.None: return historyFailure[seq[byte]](selected.error)
  if array[32, byte](selected.value.rowDigest) != array[32, byte](row.rowDigest):
    return historyFailure[seq[byte]](HistoryError.StaleSelection)
  let read = readBoundedFile(ordinalPath(selection.files, row.ordinal, true), recordBytes)
  if read.error != AtomicFileError.None: return historyFailure[seq[byte]](fileReason(read.error))
  historySuccess(read.value)

proc unlinkIfPresent(path: string): HistoryError =
  ## Cleanup is idempotent after interrupted reclamation; unrelated native failures remain explicit.
  var name = path
  if posix.unlink(name.toCString()) == 0 or errno() == ENOENT: return HistoryError.None
  HistoryError.IoFailure

proc cleanupProgress(files: HistoryFiles, cursor: HistoryCursor): HistoryResult[uint64] =
  ## A checksum-protected watermark tracks physical reclamation only; the canonical cursor alone selects availability.
  const magic = "RAGNAROK-HISTORY-CLEANUP-V1\n"
  let path = files.folder & "/CLEANUP"
  if absent(path): return historySuccess(1'u64)
  let read = readBoundedFile(path, ByteLimit(112))
  if read.error != AtomicFileError.None: return historyFailure[uint64](fileReason(read.error))
  let bytes = read.value
  if bytes.len != 112: return historyFailure[uint64](HistoryError.InvalidFormat)
  for index in 0..<32:
    let expected = if index < magic.len: byte(magic[index]) else: 0'u8
    if bytes[index] != expected: return historyFailure[uint64](HistoryError.InvalidFormat)
  let chain = array[32, byte](files.chain)
  for index in 0..<32:
    if bytes[32+index] != chain[index]: return historyFailure[uint64](HistoryError.WrongChain)
  var first = 0'u64
  var last = 0'u64
  for index in 0..<8:
    first = first or (uint64(bytes[64+index]) shl (index*8))
    last = last or (uint64(bytes[72+index]) shl (index*8))
  if first == 0 or first > uint64(cursor.firstOrdinal) or last > uint64(cursor.lastOrdinal):
    return historyFailure[uint64](HistoryError.StaleSelection)
  let digest = blake2b256(bytes.toOpenArray(0, 79))
  if digest.error != CryptoError.None: return historyFailure[uint64](HistoryError.BackendFailure)
  let expected = array[32, byte](digest.value)
  for index in 0..<32:
    if bytes[80+index] != expected[index]: return historyFailure[uint64](
        HistoryError.ChecksumMismatch)
  historySuccess(first)

proc saveCleanupProgress(files: HistoryFiles, cursor: HistoryCursor): HistoryError =
  ## Publish a progress acknowledgement only after every older file deletion and directory sync succeeded.
  const magic = "RAGNAROK-HISTORY-CLEANUP-V1\n"
  var bytes = default(array[112, byte])
  for index, character in magic: bytes[index] = byte(character)
  let chain = array[32, byte](files.chain)
  for index in 0..<32: bytes[32+index] = chain[index]
  for index in 0..<8:
    bytes[64+index] = byte((uint64(cursor.firstOrdinal) shr (index*8)) and 255)
    bytes[72+index] = byte((uint64(cursor.lastOrdinal) shr (index*8)) and 255)
  let digest = blake2b256(bytes.toOpenArray(0, 79))
  if digest.error != CryptoError.None: return HistoryError.BackendFailure
  let hash = array[32, byte](digest.value)
  for index in 0..<32: bytes[80+index] = hash[index]
  fileReason(replaceAtomicFile(files.folder & "/CLEANUP", bytes, ByteLimit(112)))

proc pruneHistoryFiles*(files: HistoryFiles, before, selected: HistoryCursor,
    resetProgress = false): HistoryResult[uint64] =
  ## Call only after confirmed canonical selection. Failures never roll back the selected cursor or invalidate loaded readers.
  if not files.ready or not before.initialized or not selected.initialized:
    return historyFailure[uint64](HistoryError.Uninitialized)
  if array[32, byte](before.chainId) != array[32, byte](files.chain) or
      array[32, byte](selected.chainId) != array[32, byte](files.chain):
    return historyFailure[uint64](HistoryError.WrongChain)
  if uint64(selected.firstOrdinal) < uint64(before.firstOrdinal) or
      uint64(selected.lastOrdinal) < uint64(before.lastOrdinal):
    return historyFailure[uint64](HistoryError.StaleSelection)
  if uint64(selected.lastOrdinal) == 0: return historySuccess(0'u64)
  if resetProgress:
    let reset = unlinkIfPresent(files.folder & "/CLEANUP")
    if reset != HistoryError.None: return historyFailure[uint64](
        reset) # A newly selected legacy seed has its own complete staged ordinal inventory.
  let progress = cleanupProgress(files, selected)
  if progress.error != HistoryError.None: return historyFailure[uint64](progress.error)
  var index = progress.value
  var retired = 0'u64
  while index > 0 and index < uint64(selected.firstOrdinal):
    let path = ordinalPath(files, HistoryOrdinal(index), false)
    if not absent(path):
      let row = readRawRow(files, HistoryOrdinal(index))
      if row.error != HistoryError.None: return historyFailure[uint64](row.error)
      let alias = unlinkIfPresent(hashPath(files, row.value.blockHash))
      if alias != HistoryError.None: return historyFailure[uint64](alias)
      let payload = unlinkIfPresent(ordinalPath(files, HistoryOrdinal(index), true))
      if payload != HistoryError.None: return historyFailure[uint64](payload)
      let removed = unlinkIfPresent(path)
      if removed != HistoryError.None: return historyFailure[uint64](removed)
    inc retired
    inc index # index is strictly below selected.first, so both increments cannot overflow.
  if retired == 0 and not resetProgress: return historySuccess(
      0'u64) # Confirmed progress avoids rescanning a long already reclaimed prefix.
  let synced = syncDirectory(files.folder)
  if synced != HistoryError.None: return historyFailure[uint64](synced)
  let recorded = saveCleanupProgress(files, selected)
  if recorded != HistoryError.None: return historyFailure[uint64](recorded)
  historySuccess(retired)

proc copyHistoricalSelection*(source: CheckedHistorySelection, folder: string,
    recordBytes: ByteLimit): HistoryResult[CheckedHistorySelection] =
  ## Stream a selected suffix into an exclusively created destination before its primary canonical context is selected.
  ## A failed copy leaves an unselected forensic namespace; callers never replace an existing published catalog.
  if not source.ready: return historyFailure[CheckedHistorySelection](HistoryError.Uninitialized)
  let opened = openHistoryFiles(folder, source.cursor.chainId, create = true, exclusive = true)
  if opened.error != HistoryError.None: return historyFailure[CheckedHistorySelection](opened.error)
  let files = opened.value
  var ordinal = uint64(source.cursor.firstOrdinal)
  if uint64(source.cursor.lastOrdinal) != 0:
    while true:
      let row = source.rowAt(HistoryOrdinal(ordinal))
      if row.error != HistoryError.None: return historyFailure[CheckedHistorySelection](row.error)
      let record = source.readHistoryRecord(row.value, recordBytes)
      if record.error != HistoryError.None: return historyFailure[CheckedHistorySelection](record.error)
      let encoded = encodeHistoryRow(row.value)
      if encoded.error != HistoryError.None: return historyFailure[CheckedHistorySelection](encoded.error)
      let payload = replaceAtomicFile(ordinalPath(files, row.value.ordinal, true), record.value, recordBytes)
      if payload != AtomicFileError.None: return historyFailure[CheckedHistorySelection](fileReason(payload))
      let indexed = replaceAtomicFile(ordinalPath(files, row.value.ordinal, false), encoded.value,
          ByteLimit(HistoryRowBytes))
      if indexed != AtomicFileError.None: return historyFailure[CheckedHistorySelection](fileReason(indexed))
      let alias = replaceAtomicFile(hashPath(files, row.value.blockHash), encoded.value, ByteLimit(HistoryRowBytes))
      if alias != AtomicFileError.None: return historyFailure[CheckedHistorySelection](fileReason(alias))
      if ordinal == uint64(source.cursor.lastOrdinal): break # Terminal equality proves increment cannot wrap.
      inc ordinal
  # No excluded prefix ever existed in this fresh namespace; record that fact without scanning missing ordinals.
  let acknowledged = saveCleanupProgress(files, source.cursor)
  if acknowledged != HistoryError.None: return historyFailure[CheckedHistorySelection](acknowledged)
  validateHistorySelection(files, source.cursor, recordBytes)
