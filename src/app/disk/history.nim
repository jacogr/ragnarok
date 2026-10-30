# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local restart context retains exact headers, full profiles, roots and explicit finality.
## Root hints route historical reads; restoreDiskHead validates every hint against the enclosed identity.
import ../chain
import ./head as disk_head
import ../historical/context as historical_context
import ../../chain/[genesis, provider, parameters]
import ../../state/[store, disk_store]
import ../../storage/database_identity
import ../../storage/node/repository as node_repository
import ../../storage/history/index as history_index
import ../../codec/[bounded, header]
import ../../codec/state/trie as state_trie
import ../../codec/assurances

type
  DiskHistoryError* {.pure.} = enum ## Refusals expose no partially restored history or application owner.
    Uninitialized, None, InvalidFormat, LimitExceeded, HeadFailure, StoreFailure, ChainFailure
  DiskHistoryResult*[T] = object ## Only completely checked bytes or a complete bounded canonical view escape.
    case status: DiskHistoryError
    of None: completed: T
    else: discard # Default and failed outcomes carry reasons alone.
  HistoryFormat {.pure.} = enum Legacy, Window, Validation ## Exact known local versions; no fallback decoder.
  HeadExtent = object ## Private preflight offsets refer only to the stable borrowed context input.
    start, length: int
    root: StateRoot

const
  LegacyHistoryMagic = "RAGNAROK-DISK-CHAIN-V1\n"
  WindowHistoryMagic = "RAGNAROK-DISK-CHAIN-V2\n"
  HistoryMagic = "RAGNAROK-DISK-CHAIN-V3\n"
  HistoryPrefixBytes* = HistoryMagic.len+32 ## E8 extra-header count, capacity, state count and finality ordinal.
  WindowHistoryPrefixBytes = WindowHistoryMagic.len+24 # V2 has no independent header-only validation prefix.
  LegacyHistoryPrefixBytes = LegacyHistoryMagic.len+2 # Read/authority compatibility only; new writes use V3.
  EntryPrefixBytes = 40 # Complete posterior-root hint plus E8 exact single-head context length.

func error*[T](outcome: DiskHistoryResult[T]): DiskHistoryError =
  ## Read the selected refusal without accessing partial data.
  outcome.status

func value*[T](outcome: DiskHistoryResult[T]): T {.inline,
    requires: outcome.status == DiskHistoryError.None.} =
  ## Access only fully encoded or restored local history.
  outcome.completed

func number(bytes: openArray[byte], offset: int): uint64 =
  ## Every caller proves a complete E8 field first.
  result = 0
  for index in 0..<8: result = result or (uint64(bytes[offset+index]) shl (index*8))

proc putNumber(bytes: var seq[byte], offset: int, value: uint64) =
  ## The measured complete output owns every written field.
  for index in 0..<8: bytes[offset+index] = byte((value shr (index*8)) and 255)

func hasMagic(bytes: openArray[byte], magic: string): bool =
  ## Inspect a known exact version prefix only after proving its complete extent.
  if bytes.len < magic.len: return false
  for index, character in magic:
    if bytes[index] != byte(character): return false # No alternate-version fallback on a mismatched prefix.
  true

proc encodeHistory(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit, format: HistoryFormat): DiskHistoryResult[
        seq[byte]] =
  ## Measure all selected sealed headers before encoding; absent finality stays explicitly absent.
  let view = owner.chainView
  let count = view.retainedCount
  let legacy = format == HistoryFormat.Legacy
  let validation = format == HistoryFormat.Validation
  let local = min(count, ValidationHeaderCapacity)
  if view.validationHeaderCount < local or view.validationHeaderCount > ValidationHeaderCapacity:
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  let extraHeaders = view.validationHeaderCount-local
  if not validation and extraHeaders != 0:
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  let capacity = view.retentionLimit
  if count == 0 or not validHistoryLimit(capacity) or uint64(count) > uint64(capacity) or
      (legacy and uint64(capacity) != uint64(MaxRetainedBlocks)):
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  let maximum = min(uint64(limit), uint64(high(int)))
  let prefix = if legacy: LegacyHistoryPrefixBytes elif validation: HistoryPrefixBytes else: WindowHistoryPrefixBytes
  if uint64(prefix) > maximum or
      uint64(count) > (maximum-uint64(prefix)) div uint64(EntryPrefixBytes+DiskHeadPrefixBytes+1):
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
  var saved: seq[BlockSnapshotResult] = @[]
  for index in 0..<count: saved.add(view.retainedBlockAt(RetainedBlockIndex(index)))
  var finality = 0'u64
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None:
    for index in 0..<count:
      if array[32, byte](saved[index].value.blockHash) == array[32, byte](
          finalized.value.blockHash):
        finality = uint64(index)+1 # In-window finality must reuse this same restored block owner.
    if finality == 0:
      finality = high(uint64)
      saved.add(finalized) # Only an explicitly selected older anchor consumes one additional slot.
  elif finalized.error != GenesisError.Unavailable:
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  var extent = uint64(prefix)
  for index in 0..<extraHeaders:
    let info = view.validationHeaderAt(ValidationHeaderIndex(index)).header.headerInfo
    if info.error != HeaderError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.HeadFailure)
    if 8'u64 > maximum-extent or uint64(info.value.consumed) > maximum-extent-8:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
    extent += 8+uint64(info.value.consumed) # A bounded header cache retains no old complete-state owners.
  if extent > maximum: return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
  for selected in saved:
    let info = selected.value.header.headerInfo
    if info.error != HeaderError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.HeadFailure)
    let headPrefix = if selected.value.hasBlockBody: DiskBodyHeadPrefixBytes else: DiskHeadPrefixBytes
    let bodyLength = if selected.value.hasBlockBody: uint64(
        selected.value.blockBodyLength) else: 0'u64
    let fixed = uint64(EntryPrefixBytes+headPrefix)
    if fixed > maximum-extent or uint64(info.value.consumed) > maximum-extent-fixed or
        bodyLength > maximum-extent-fixed-uint64(info.value.consumed):
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
    extent += fixed+uint64(info.value.consumed)+bodyLength # Subtraction checks prove allocation bounds, including complete bodies.
  var bytes = newSeq[byte](int(extent))
  if legacy:
    # V1 re-encoding authorizes only an exact existing V1 context, never a nondefault policy.
    for index, character in LegacyHistoryMagic: bytes[index] = byte(character)
    bytes[LegacyHistoryMagic.len] = byte(count)
    bytes[LegacyHistoryMagic.len+1] = if finality == high(uint64): 255'u8 else: byte(finality)
  else:
    # V3 keeps extra validation headers independently from the full-state window; V2 authority stays byte exact.
    let magic = if validation: HistoryMagic else: WindowHistoryMagic
    for index, character in magic: bytes[index] = byte(character)
    let scalar = magic.len+(if validation: 8 else: 0)
    if validation: putNumber(bytes, magic.len, uint64(extraHeaders))
    putNumber(bytes, scalar, uint64(capacity))
    putNumber(bytes, scalar+8, uint64(count))
    putNumber(bytes, scalar+16, finality)
  var offset = prefix
  for index in 0..<extraHeaders:
    let owner = view.validationHeaderAt(ValidationHeaderIndex(index)).header
    let size = owner.headerInfo.value.consumed
    putNumber(bytes, offset, uint64(size))
    offset += 8
    if encodeOwnedHeader(owner, bytes.toOpenArray(offset, offset+size-1)).error != HeaderError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.HeadFailure)
    offset += size
  for selected in saved:
    let single = initApplicationChain(genesisView(selected))
    if single.error != ApplicationChainError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
    let encoded = encodeDiskHead(single.value, chain, generation, limit)
    if encoded.error != DiskHeadError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.HeadFailure)
    let root = array[32, byte](selected.value.stateRoot)
    for index in 0..<32: bytes[offset+index] = root[index]
    let head = encoded.value
    putNumber(bytes, offset+32, uint64(head.len))
    offset += EntryPrefixBytes
    for index, octet in head: bytes[offset+index] = octet
    offset += head.len
  DiskHistoryResult[seq[byte]](status: DiskHistoryError.None, completed: bytes)

proc encodeDiskHistory*(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit): DiskHistoryResult[seq[byte]] =
  ## New durable publications write V3, preserving header-only validation anchors independently of full-state retention.
  encodeHistory(owner, chain, generation, limit, HistoryFormat.Validation)

proc encodeMatchingDiskHistory*(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit,
    reference: openArray[byte]): DiskHistoryResult[seq[byte]] =
  ## Re-encode authority in the stored version for an exact byte comparison before mutation.
  if hasHistoricalContext(reference):
    let indexed = decodeHistoricalContext(reference, chain, limit)
    if indexed.error != HistoryError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.InvalidFormat)
    if uint64(limit) < uint64(HistoricalContextPrefixBytes):
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
    let budget = ByteLimit(uint64(limit)-uint64(HistoricalContextPrefixBytes))
    let inner = encodeMatchingDiskHistory(owner, chain, generation, budget,
        indexed.value.chainContext)
    if inner.error != DiskHistoryError.None: return inner
    let encoded = encodeHistoricalContext(indexed.value.historicalCursor, inner.value, limit)
    if encoded.error != HistoryError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.None, completed: encoded.value)
  if hasMagic(reference, HistoryMagic): return encodeHistory(owner, chain, generation, limit,
      HistoryFormat.Validation)
  if hasMagic(reference, WindowHistoryMagic): return encodeHistory(owner, chain, generation, limit,
      HistoryFormat.Window)
  if hasMagic(reference, LegacyHistoryMagic): return encodeHistory(owner, chain, generation, limit,
      HistoryFormat.Legacy)
  DiskHistoryResult[seq[byte]](status: DiskHistoryError.InvalidFormat)

proc restoreDiskHistory*(bytes: openArray[byte], chain: StorageChainId,
    generation: RepositoryGeneration, configuration: Parameters, disk: DiskStateStore,
    policy: StateStoreLimits, limit: ByteLimit): DiskHistoryResult[ApplicationChain] =
  ## Only journal-verified local context supplies ancestry authority; external imports use their trust path.
  ## Validate every extent before graph restoration and preserve the disk owner's exact current snapshot.
  if hasHistoricalContext(bytes):
    let indexed = decodeHistoricalContext(bytes, chain, limit)
    if indexed.error != HistoryError.None:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
    let restored = restoreDiskHistory(indexed.value.chainContext, chain, generation, configuration,
      disk, policy, limit)
    if restored.error != DiskHistoryError.None: return restored
    let head = restored.value.chainView.bestBlock.value
    let cursor = indexed.value.historicalCursor
    if array[32, byte](head.blockHash) != array[32, byte](cursor.selectedHash) or head.slot !=
        cursor.selectedSlot:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
    return restored
  if uint64(bytes.len) > uint64(limit):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.LimitExceeded)
  let legacy = hasMagic(bytes, LegacyHistoryMagic)
  let validation = hasMagic(bytes, HistoryMagic)
  let window = hasMagic(bytes, WindowHistoryMagic)
  let prefix = if legacy: LegacyHistoryPrefixBytes elif validation: HistoryPrefixBytes else: WindowHistoryPrefixBytes
  if (not legacy and not validation and not window) or bytes.len < prefix:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let scalar = HistoryMagic.len+(if validation: 8 else: 0)
  let capacity = if legacy: uint64(MaxRetainedBlocks) else: number(bytes, scalar)
  let countValue = if legacy: uint64(bytes[LegacyHistoryMagic.len]) else: number(bytes, scalar+8)
  let rawTag = if legacy: uint64(bytes[LegacyHistoryMagic.len+1]) else: number(bytes, scalar+16)
  let extraHeaders = if validation: number(bytes, HistoryMagic.len) else: 0'u64
  let tag = if legacy and rawTag == 255: high(uint64) else: rawTag
  if not validHistoryLimit(ElementLimit(capacity)) or countValue == 0 or countValue > capacity or
      (tag > countValue and tag != high(uint64)):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  if extraHeaders > uint64(ValidationHeaderCapacity)-min(countValue, uint64(
      ValidationHeaderCapacity)):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  var headers: seq[OwnedHeader] = @[]
  var offset = prefix
  if extraHeaders > 0:
    let cores = configuration.get(coreCount)
    if cores > 341: return DiskHistoryResult[ApplicationChain](
        status: DiskHistoryError.InvalidFormat)
    let config = HeaderConfig(cores: CoreCount(cores), authorValidators: ValidatorCount(cores*3),
      epochSlots: EpochSlots(configuration.get(epochPeriod)), maxBytes: ByteLimit(256*1024))
    for index in 0..<int(extraHeaders):
      if bytes.len-offset < 8: return DiskHistoryResult[ApplicationChain](
          status: DiskHistoryError.InvalidFormat)
      let size = number(bytes, offset)
      offset += 8
      if size == 0 or size > 262144'u64 or size > uint64(bytes.len-offset):
        return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
      let decoded = decodeHeader(bytes.toOpenArray(offset, offset+int(size)-1), config)
      if decoded.error != HeaderError.None or decoded.value.consumed != int(size):
        return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.HeadFailure)
      headers.add(decoded.value.owner)
      offset += int(size) # Actual input bounds prove conversion and every offset update.
  let extra = if tag == high(uint64): 1'u64 else: 0'u64
  # Count-sized extent storage is admitted from actual remaining head bytes after the bounded header-only prefix.
  let available = uint64((bytes.len-offset) div (EntryPrefixBytes+DiskHeadPrefixBytes+1))
  if countValue > available or extra > available-countValue:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let count = int(countValue)
  let total = count+int(extra)
  var extents = newSeq[HeadExtent](total)
  for index in 0..<total:
    if bytes.len-offset < EntryPrefixBytes:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
    var root = default(array[32, byte])
    for octet in 0..<32: root[octet] = bytes[offset+octet]
    let length = number(bytes, offset+32)
    offset += EntryPrefixBytes
    if length <= uint64(DiskHeadPrefixBytes) or length > uint64(bytes.len-offset):
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
    extents[index] = HeadExtent(start: offset, length: int(length), root: StateRoot(root))
    offset += int(length) # Proved within the input before narrowing or adding.
  if offset != bytes.len:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let current = disk.snapshot
  let revision = disk.generation
  if current.error != DiskStoreError.None or revision.error != DiskStoreError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.StoreFailure)
  let requested = newStateStore([], policy)
  if requested.error != StateStoreError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.StoreFailure)
  if uint64(revision.value) != uint64(generation) or
      array[32, byte](extents[count-1].root) != array[32, byte](current.value.commitment.root) or
      not sameStateStorePolicy(current.value, requested.value.snapshot.value):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.StoreFailure)
  var restored: seq[BlockSnapshotResult] = @[]
  for index in 0..<total:
    let extent = extents[index]
    let snapshot = if index == count-1: current else: disk.restoreDiskSnapshot(extent.root, policy)
    if snapshot.error != DiskStoreError.None:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.StoreFailure)
    let head = restoreDiskHead(bytes.toOpenArray(extent.start, extent.start+extent.length-1),
      chain, generation, configuration, snapshot.value, limit)
    if head.error != DiskHeadError.None:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.HeadFailure)
    restored.add(head.value.chainView.bestBlock)
  let finalized = if tag == 0: unavailableGenesis()
    elif tag == high(uint64): restored[count]
    else: restored[int(tag)-1]
  let history = restoreLocalChainView(restored.toOpenArray(0, count-1), finalized, ElementLimit(capacity))
  if history.error != ViewAdvanceError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
  var view = history.value
  if extraHeaders > 0:
    for index in 0..<view.validationHeaderCount:
      headers.add(view.validationHeaderAt(ValidationHeaderIndex(index)).header)
    let cached = view.withValidationHeaders(headers)
    if cached.error != ViewAdvanceError.None:
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
    view = cached.value
  let owner = initApplicationChain(view)
  if owner.error != ApplicationChainError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
  DiskHistoryResult[ApplicationChain](status: DiskHistoryError.None, completed: owner.value)
