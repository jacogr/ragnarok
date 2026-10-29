# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable compressed 256-bit historical index keeps memory-backend archives out of the rolling view.
## Each append copies at most one hash path; cached ordinal ranges prune bounded history without a list.
import std/assertions
import ./genesis
import ../storage/history/index as history_index
import ../storage/database_identity

type
  HistoryNode = ref object ## Strictly increasing branch bits bound traversal depth to 256; leaves own exact snapshots.
    split: int
    key: array[32, byte]
    oldest, newest: uint64
    zero, one: nil HistoryNode
    saved: BlockSnapshotResult
  MemoryHistoryData = ref object ## Private immutable root and scalar cursor share no mutable external storage.
    cursor: HistoryCursor
    root: nil HistoryNode
  MemoryHistory* = object ## Copies retain immutable index versions; default means historical indexing disabled.
    head: nil MemoryHistoryData

func initialized*(history: MemoryHistory): bool =
  ## Defaults contain neither an implicit archive nor a fabricated genesis.
  history.head != nil
func sameMemoryHistory*(left, right: MemoryHistory): bool =
  ## Publication joins only one exact immutable index version, including a matching disabled default.
  left.head == right.head
func historyCursor*(history: MemoryHistory): HistoryCursor {.requires: history.initialized.} =
  ## Copy policy/ordinal facts without retaining or copying an archive-sized container.
  let head = history.head
  assert head != nil
  head.cursor
func bit(key: array[32, byte], index: int): int {.requires: index >= 0 and index < 256.} =
  ## Big-endian bit order is local index ordering, independent of JAM trie encoding.
  int((key[index div 8] shr (7-index mod 8)) and 1)
func branch(split: int, zero, one: HistoryNode): HistoryNode =
  ## Construct an immutable two-child node with exact ordinal bounds and no parent reference.
  let oldest = if zero.oldest < one.oldest: zero.oldest else: one.oldest
  let newest = if zero.newest > one.newest: zero.newest else: one.newest
  HistoryNode(split: split, zero: zero, one: one, oldest: oldest, newest: newest)
func insertAt(node: HistoryNode, leaf: HistoryNode, split: int): HistoryNode =
  ## Insert above the first later split; each recursive branch consumes a strictly greater bit.
  if node.split >= split:
    if bit(leaf.key, split) == 0: return branch(split, leaf, node)
    return branch(split, node, leaf)
  let zero = node.zero
  let one = node.one
  assert zero != nil and one != nil # Only a terminal leaf has absent children and its split is 256.
  if bit(leaf.key, node.split) == 0:
    return branch(node.split, insertAt(zero, leaf, split), one)
  branch(node.split, zero, insertAt(one, leaf, split))
func insert(root: nil HistoryNode, saved: BlockSnapshotResult, ordinal: uint64): nil HistoryNode =
  ## Find the existing terminal key before allocating one leaf and the copied compressed path.
  let key = array[32, byte](saved.value.blockHash)
  let leaf = HistoryNode(split: 256, key: key, oldest: ordinal, newest: ordinal, saved: saved)
  if root == nil: return leaf
  var selected: HistoryNode = root
  while selected.split < 256:
    let child = if bit(key, selected.split) == 0: selected.zero else: selected.one
    assert child != nil
    selected = child # Increasing split values prove the fixed 256-bit traversal ceiling.
  var difference = 0
  while difference < 256 and bit(key, difference) == bit(selected.key, difference):
    inc difference # Short-circuiting prevents a bit access beyond the full 32-byte identity.
  if difference == 256: return nil # A duplicate identity cannot overwrite a previously accepted snapshot.
  insertAt(root, leaf, difference)
func trim(node: nil HistoryNode, first: uint64): nil HistoryNode =
  ## Drop old subtrees; ordinary bounded appends expire at most one ordinal and visit at most one full key path.
  if node == nil or node.newest < first: return nil
  if node.oldest >= first: return node # Entire immutable subtrees remain shared when no ordinal expires.
  let zero = trim(node.zero, first)
  let one = trim(node.one, first)
  if zero == nil: return one # Collapsing empty branches preserves strictly increasing split order.
  if one == nil: return zero
  branch(node.split, zero, one)
proc append*(history: MemoryHistory, saved: BlockSnapshotResult): HistoryResult[MemoryHistory] =
  ## Stage exact scalar/index replacements before canonical state/view publication.
  let head = history.head
  if head == nil: return historyFailure[MemoryHistory](HistoryError.Uninitialized)
  if saved.error != GenesisError.None: return historyFailure[MemoryHistory](
      HistoryError.InvalidFormat)
  let snapshot = saved.value
  let body = if snapshot.hasBlockBody: HistoryDigest(snapshot.blockBodyDigest) else: default(HistoryDigest)
  let prepared = prepareHistoryAppend(head.cursor, HistoryBlockHash(array[32, byte](
      snapshot.blockHash)),
    HistoryBlockHash(array[32, byte](snapshot.parentHash)), snapshot.stateRoot, snapshot.slot,
    snapshot.hasBlockBody, body)
  if prepared.error != HistoryError.None: return historyFailure[MemoryHistory](prepared.error)
  let next = prepared.value.nextCursor
  let inserted = insert(head.root, saved, uint64(next.lastOrdinal))
  if inserted == nil: return historyFailure[MemoryHistory](HistoryError.InvalidFormat)
  let retained = trim(inserted, uint64(next.firstOrdinal))
  historySuccess(MemoryHistory(head: MemoryHistoryData(cursor: next, root: retained)))
proc newMemoryHistory*(saved: openArray[BlockSnapshotResult],
    policy: HistoryPolicy): HistoryResult[MemoryHistory] =
  ## Seed only available snapshots; neither archive nor a larger bounded policy invents missing earlier data.
  let cursor = initHistoryCursor(default(StorageChainId), policy)
  if cursor.error != HistoryError.None: return historyFailure[MemoryHistory](cursor.error)
  var working = MemoryHistory(head: MemoryHistoryData(cursor: cursor.value))
  for snapshot in saved:
    let next = working.append(snapshot)
    if next.error != HistoryError.None: return historyFailure[MemoryHistory](next.error)
    working = next.value # Every failure retires the private construction prefix.
  historySuccess(working)
proc withHistoryPolicy*(history: MemoryHistory, policy: HistoryPolicy): HistoryResult[
    MemoryHistory] =
  ## Policy shrink copies only affected branches; old readers retain their prior complete states and bodies.
  let head = history.head
  if head == nil: return historyFailure[MemoryHistory](HistoryError.Uninitialized)
  let cursor = head.cursor.withHistoryPolicy(policy)
  if cursor.error != HistoryError.None: return historyFailure[MemoryHistory](cursor.error)
  if sameHistoryCursor(head.cursor, cursor.value): return historySuccess(
      history) # Reapplying the selected policy preserves exact owner identity.
  historySuccess(MemoryHistory(head: MemoryHistoryData(cursor: cursor.value,
    root: trim(head.root, uint64(cursor.value.firstOrdinal)))))
func blockAt*(history: MemoryHistory, hash: BlockHash): BlockSnapshotResult =
  ## At most 256 branch decisions and one exact full-hash comparison; no archive-sized scan or cache.
  let head = history.head
  if head == nil: return unavailableGenesis()
  let key = array[32, byte](hash)
  var node = head.root
  while node != nil:
    if node.split == 256:
      if node.key == key: return node.saved
      return unavailableGenesis() # A neighboring terminal key proves local historical unavailability.
    node = if bit(key, node.split) == 0: node.zero else: node.one
  unavailableGenesis()
