# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local restart context retains exact headers, full profiles, roots and explicit finality.
## Root hints route historical reads; restoreDiskHead validates every hint against the enclosed identity.
import ./[chain, disk_head]
import ../chain/[genesis, provider, parameters]
import ../state/[store, disk_store]
import ../storage/[database_identity, node_repository]
import ../codec/[bounded, header, state_trie]

type
  DiskHistoryError* {.pure.} = enum ## Refusals expose no partially restored history or application owner.
    Uninitialized, None, InvalidFormat, LimitExceeded, HeadFailure, StoreFailure, ChainFailure
  DiskHistoryResult*[T] = object ## Only completely checked bytes or a complete bounded canonical view escape.
    case status: DiskHistoryError
    of None: completed: T
    else: discard # Default and failed outcomes carry reasons alone.
  HeadExtent = object ## Private preflight offsets refer only to the stable borrowed context input.
    start, length: int
    root: StateRoot

const
  LegacyHistoryMagic = "RAGNAROK-DISK-CHAIN-V1\n"
  HistoryMagic = "RAGNAROK-DISK-CHAIN-V2\n"
  HistoryPrefixBytes* = HistoryMagic.len+24 ## E8 capacity, count and explicit finality ordinal.
  LegacyHistoryPrefixBytes = LegacyHistoryMagic.len+2 # Read/authority compatibility only; new writes use V2.
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
    generation: RepositoryGeneration, limit: ByteLimit, legacy: bool): DiskHistoryResult[seq[byte]] =
  ## Measure all selected sealed headers before encoding; absent finality stays explicitly absent.
  let view = owner.chainView
  let count = view.retainedCount
  let capacity = view.retentionLimit
  if count == 0 or not validHistoryLimit(capacity) or uint64(count) > uint64(capacity) or
      (legacy and uint64(capacity) != uint64(MaxRetainedBlocks)):
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  let maximum = min(uint64(limit), uint64(high(int)))
  let prefix = if legacy: LegacyHistoryPrefixBytes else: HistoryPrefixBytes
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
    # V2 widens every ordinal and persists policy independently of the number of available entries.
    for index, character in HistoryMagic: bytes[index] = byte(character)
    putNumber(bytes, HistoryMagic.len, uint64(capacity))
    putNumber(bytes, HistoryMagic.len+8, uint64(count))
    putNumber(bytes, HistoryMagic.len+16, finality)
  var offset = prefix
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
  ## New durable publications always write V2; format migration shares normal atomic publication.
  encodeHistory(owner, chain, generation, limit, false)
proc encodeMatchingDiskHistory*(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit,
    reference: openArray[byte]): DiskHistoryResult[seq[byte]] =
  ## Re-encode authority in the stored version for an exact byte comparison before mutation.
  if hasMagic(reference, HistoryMagic): return encodeHistory(owner, chain, generation, limit, false)
  if hasMagic(reference, LegacyHistoryMagic): return encodeHistory(owner, chain, generation, limit, true)
  DiskHistoryResult[seq[byte]](status: DiskHistoryError.InvalidFormat)
proc restoreDiskHistory*(bytes: openArray[byte], chain: StorageChainId,
    generation: RepositoryGeneration, configuration: Parameters, disk: DiskStateStore,
    policy: StateStoreLimits, limit: ByteLimit): DiskHistoryResult[ApplicationChain] =
  ## Only journal-verified local context supplies ancestry authority; external imports use their trust path.
  ## Validate every extent before graph restoration and preserve the disk owner's exact current snapshot.
  if uint64(bytes.len) > uint64(limit):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.LimitExceeded)
  let legacy = hasMagic(bytes, LegacyHistoryMagic)
  let prefix = if legacy: LegacyHistoryPrefixBytes else: HistoryPrefixBytes
  if (not legacy and not hasMagic(bytes, HistoryMagic)) or bytes.len < prefix:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let capacity = if legacy: uint64(MaxRetainedBlocks) else: number(bytes, HistoryMagic.len)
  let countValue = if legacy: uint64(bytes[LegacyHistoryMagic.len]) else: number(bytes,
      HistoryMagic.len+8)
  let rawTag = if legacy: uint64(bytes[LegacyHistoryMagic.len+1]) else: number(bytes,
      HistoryMagic.len+16)
  let tag = if legacy and rawTag == 255: high(uint64) else: rawTag
  if not validHistoryLimit(ElementLimit(capacity)) or countValue == 0 or countValue > capacity or
      (tag > countValue and tag != high(uint64)):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let extra = if tag == high(uint64): 1'u64 else: 0'u64
  # A minimal entry requires both fixed prefixes and at least one header byte. Prove a count-sized
  # allocation from actual input bytes before converting counts or reserving extent storage.
  let available = uint64((bytes.len-prefix) div (EntryPrefixBytes+DiskHeadPrefixBytes+1))
  if countValue > available or extra > available-countValue:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let count = int(countValue)
  let total = count+int(extra) # Input-derived bound also proves host addition and allocation extents.
  var extents = newSeq[HeadExtent](total)
  var offset = prefix
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
  let owner = initApplicationChain(history.value)
  if owner.error != ApplicationChainError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
  DiskHistoryResult[ApplicationChain](status: DiskHistoryError.None, completed: owner.value)
