# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local restart context retains exact headers, full profiles, roots and explicit finality.
## Root hints route historical reads; restoreDiskHead validates every hint against the enclosed identity.
import ./chain as app_chain
import ./disk_head as app_disk_head
import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../chain/parameters as chain_parameters
import ../state/store as state_store
import ../state/disk_store as state_disk_store
import ../storage/database_identity as storage_database_identity
import ../storage/node_repository as storage_node_repository
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../codec/state_trie as codec_state_trie

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
  HistoryMagic = "RAGNAROK-DISK-CHAIN-V1\n"
  HistoryPrefixBytes* = HistoryMagic.len+2 ## Version followed by retained count and explicit finality tag.
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
proc encodeDiskHistory*(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit): DiskHistoryResult[seq[byte]] =
  ## Measure all at-most-nine sealed headers before encoding; absent finality stays explicitly absent.
  let view = owner.chainView
  let count = view.retainedCount
  if count == 0 or count > MaxRetainedBlocks:
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  var saved: seq[BlockSnapshotResult] = @[]
  for index in 0..<count: saved.add(view.retainedBlockAt(RetainedBlockIndex(index)))
  var finality = 0'u8
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None:
    for index in 0..<count:
      if array[32, byte](saved[index].value.blockHash) == array[32, byte](
          finalized.value.blockHash):
        finality = byte(index+1) # In-window finality must reuse this same restored block owner.
    if finality == 0:
      finality = 255
      saved.add(finalized) # Only an explicitly selected older anchor consumes the ninth slot.
  elif finalized.error != GenesisError.Unavailable:
    return DiskHistoryResult[seq[byte]](status: DiskHistoryError.ChainFailure)
  let maximum = min(uint64(limit), uint64(high(int)))
  var extent = uint64(HistoryPrefixBytes)
  if extent > maximum: return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
  for selected in saved:
    let info = selected.value.header.headerInfo
    if info.error != HeaderError.None:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.HeadFailure)
    let fixed = uint64(EntryPrefixBytes+DiskHeadPrefixBytes)
    if fixed > maximum-extent or uint64(info.value.consumed) > maximum-extent-fixed:
      return DiskHistoryResult[seq[byte]](status: DiskHistoryError.LimitExceeded)
    extent += fixed+uint64(info.value.consumed) # Subtraction checks prove both arithmetic and host allocation bounds.
  var bytes = newSeq[byte](int(extent))
  for index, character in HistoryMagic: bytes[index] = byte(character)
  bytes[HistoryMagic.len] = byte(count)
  bytes[HistoryMagic.len+1] = finality
  var offset = HistoryPrefixBytes
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
proc restoreDiskHistory*(bytes: openArray[byte], chain: StorageChainId,
    generation: RepositoryGeneration, configuration: Parameters, disk: DiskStateStore,
    policy: StateStoreLimits, limit: ByteLimit): DiskHistoryResult[ApplicationChain] =
  ## Only journal-verified local context supplies ancestry authority; external imports use their trust path.
  ## Validate every extent before graph restoration and preserve the disk owner's exact current snapshot.
  if uint64(bytes.len) > uint64(limit):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.LimitExceeded)
  if bytes.len < HistoryPrefixBytes:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  for index, character in HistoryMagic:
    if bytes[index] != byte(character):
      return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let count = int(bytes[HistoryMagic.len])
  let tag = int(bytes[HistoryMagic.len+1])
  if count == 0 or count > MaxRetainedBlocks or (tag > count and tag != 255):
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.InvalidFormat)
  let total = count+(if tag == 255: 1 else: 0)
  var extents = default(array[MaxRetainedBlocks+1, HeadExtent])
  var offset = HistoryPrefixBytes
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
    elif tag == 255: restored[count]
    else: restored[tag-1]
  let history = restoreLocalChainView(restored.toOpenArray(0, count-1), finalized)
  if history.error != ViewAdvanceError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
  let owner = initApplicationChain(history.value)
  if owner.error != ApplicationChainError.None:
    return DiskHistoryResult[ApplicationChain](status: DiskHistoryError.ChainFailure)
  DiskHistoryResult[ApplicationChain](status: DiskHistoryError.None, completed: owner.value)
