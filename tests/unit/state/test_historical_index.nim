# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "historical_index_arc_release"}

## Fixed metadata and immutable memory archives preserve exact selection without widening protocol lookup history.
import std/[assertions, syncio]
import ../../support/[disk_history_context, arc_evidence]
import ../../../src/storage/history/index as history_index
import ../../../src/storage/database_identity
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie

proc codecWitness() =
  ## E8 counters, exact versions, opaque defaults and malformed rows refuse before count-sized allocation.
  let chain = default(StorageChainId)
  assert boundedHistoryPolicy(0).error == HistoryError.InvalidPolicy
  assert boundedHistoryPolicy(high(uint64)).error == HistoryError.None
  let absent = default(HistoryPolicy)
  assert initHistoryCursor(chain, absent).error == HistoryError.InvalidPolicy
  var cursor = initHistoryCursor(chain, archiveHistoryPolicy()).value
  var parent = default(HistoryBlockHash)
  var last = default(HistoryRow)
  for ordinal in 1..300:
    var hash = default(array[32, byte])
    hash[0] = byte((ordinal shr 8) and 255)
    hash[1] = byte(ordinal and 255)
    let prepared = prepareHistoryAppend(cursor, HistoryBlockHash(hash), parent,
      default(StateRoot), uint32(ordinal*2), false)
    assert prepared.error == HistoryError.None
    assert uint64(prepared.value.indexRow.ordinal) == uint64(ordinal)
    cursor = prepared.value.nextCursor
    parent = HistoryBlockHash(hash)
    last = prepared.value.indexRow
  assert cursor.len == 300 and cursor.selectedSlot == 600 # Slot gaps do not consume local ordinals.
  let encoded = encodeHistoryCursor(cursor).value
  let restored = decodeHistoryCursor(encoded, chain)
  assert restored.error == HistoryError.None and sameHistoryCursor(cursor, restored.value)
  for stop in 0..<encoded.len:
    assert decodeHistoryCursor(encoded.toOpenArray(0, stop-1), chain).error ==
        HistoryError.InvalidFormat
  var invalid = encoded
  invalid[92] = 1
  assert decodeHistoryCursor(invalid, chain).error == HistoryError.InvalidFormat
  var wrong = default(array[32, byte])
  wrong[0] = 1
  assert decodeHistoryCursor(encoded, StorageChainId(wrong)).error == HistoryError.WrongChain
  let row = encodeHistoryRow(last).value
  assert decodeHistoryRow(row).value.rowDigest == last.rowDigest
  for stop in 0..<row.len:
    assert decodeHistoryRow(row.toOpenArray(0, stop-1)).error == HistoryError.InvalidFormat
  var changed = row
  changed[208] = changed[208] xor 1
  assert decodeHistoryRow(changed).error == HistoryError.ChecksumMismatch
  assert prepareHistoryAppend(cursor, parent, default(HistoryBlockHash), default(StateRoot),
    601, false).error == HistoryError.NotChild
  assert prepareHistoryAppend(cursor, parent, parent, default(StateRoot),
    600, false).error == HistoryError.SlotNotIncreasing
  # A shape-valid exhausted cursor must refuse before attempting arithmetic or touching disk.
  invalid = encoded
  for position in 40..<56: invalid[position] = 255
  let exhausted = decodeHistoryCursor(invalid, chain).value
  assert prepareHistoryAppend(exhausted, parent, parent, default(StateRoot),
    601, false).error == HistoryError.CounterExhausted
  let narrow = cursor.withHistoryPolicy(boundedHistoryPolicy(3).value).value
  assert uint64(narrow.firstOrdinal) == 298 and narrow.len == 3
  let enlarged = narrow.withHistoryPolicy(archiveHistoryPolicy()).value
  assert enlarged.len == 3 and uint64(enlarged.firstOrdinal) == 298 # No implicit backfill after pruning.+
proc memoryWitness() {.raises.} =
  ## Full history has a compressed immutable index; the protocol view keeps only its original bounded suffix.
  let fixture = diskHistoryFixture(96)
  let seed = genesisView(fixture.blocks[0]).finalizeView(fixture.blocks[0].value.blockHash).value
  var view = seed.withHistoricalPolicy(archiveHistoryPolicy()).value
  let original = view
  for index in 1..<fixture.blocks.len:
    view = view.advanceView(fixture.blocks[index]).value
  assert view.retainedCount == MaxRetainedBlocks and view.historicalCursor.len == 97
  assert sameChainView(view, view.withHistoricalPolicy(archiveHistoryPolicy()).value)
  assert original.retainedCount == 1 and original.historicalCursor.len == 1
  assert view.blockAt(fixture.blocks[1].value.blockHash).error == GenesisError.Unavailable
  for selected in fixture.blocks:
    let found = view.historicalBlockAt(selected.value.blockHash)
    assert found.error == GenesisError.None
    assert sameStateSnapshot(found.value.stateSnapshot, selected.value.stateSnapshot)
  let held = view.historicalBlockAt(fixture.blocks[1].value.blockHash).value
  let pruned = view.withHistoricalPolicy(boundedHistoryPolicy(3).value).value
  assert pruned.historicalCursor.len == 3 and pruned.retainedCount == MaxRetainedBlocks
  assert pruned.historicalBlockAt(fixture.blocks[1].value.blockHash).error ==
      GenesisError.Unavailable
  assert view.historicalBlockAt(fixture.blocks[1].value.blockHash).error == GenesisError.None
  assert sameStateSnapshot(held.stateSnapshot, fixture.blocks[1].value.stateSnapshot)
  assert sameStateSnapshot(pruned.bestBlock.value.stateSnapshot, view.bestBlock.value.stateSnapshot)
  let anchor = pruned.historicalBlockAt(fixture.blocks[0].value.blockHash)
  assert anchor.error == GenesisError.None # Explicit finality remains available outside the user window.
  let validation = fixture.blocks[fixture.blocks.len-5].value.blockHash
  assert pruned.blockAt(validation).error == GenesisError.None
  assert pruned.historicalBlockAt(validation).error == GenesisError.Unavailable
  let enlarged = pruned.withHistoricalPolicy(archiveHistoryPolicy()).value
  assert enlarged.historicalCursor.len == 3
  assert enlarged.historicalBlockAt(fixture.blocks[1].value.blockHash).error ==
      GenesisError.Unavailable
  assert not sameChainView(enlarged, pruned) # Identical current state cannot substitute another selected policy/index owner.
  let short = view.withRetentionLimit(ElementLimit(1)).value
  assert short.historicalCursor.len == 97 and short.retainedCount == 1
  assert short.historicalBlockAt(fixture.blocks[1].value.blockHash).error == GenesisError.None

proc releaseCycle(blocks: openArray[BlockSnapshotResult]) =
  ## One complete index lifecycle retires all copied paths, pruned versions and retained lookup owners.
  assert blocks.len >= 17
  var view = genesisView(blocks[0]).withHistoricalPolicy(archiveHistoryPolicy()).value
  for index in 1..<17: view = view.advanceView(blocks[index]).value
  let held = view.historicalBlockAt(blocks[1].value.blockHash)
  let pruned = view.withHistoricalPolicy(boundedHistoryPolicy(3).value).value
  assert held.error == GenesisError.None and pruned.historicalCursor.len == 3
proc arcWitness() {.raises.} =
  ## Fresh ARC evidence compares live bytes after identical complete immutable-index lifecycles.
  let fixture = diskHistoryFixture(16)
  releaseCycle(fixture.blocks)
  let before = getOccupiedMem()
  for iteration in 0..<1000: releaseCycle(fixture.blocks)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("historical_index", 1000, before, after)
try:
  codecWitness()
  memoryWitness()
  arcWitness()
except:
  quit(2) # Missing fixtures and invalid metadata cannot satisfy historical-index evidence.
echo "PASS historical index: E8 selection, immutable archives, exact historical state and independent protocol lookup window"
