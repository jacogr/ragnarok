# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local restoration preserves evicted and in-window finality under exact map ownership.
import std/[assertions, syncio]
import ../../support/disk_history_context
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/codec/[header, state_trie, bounded]
proc main() {.raises.} =
  ## Restore the exact newest suffix plus an older finalized anchor without silently dropping either.
  let fixture = diskHistoryFixture()
  assert fixture.view.retainedCount == MaxRetainedBlocks
  var retained: seq[BlockSnapshotResult] = @[]
  for index in 0..<fixture.view.retainedCount:
    retained.add(fixture.view.retainedBlockAt(RetainedBlockIndex(index)))
  let finalized = fixture.view.finalizedBlock
  let restored = restoreLocalChainView(retained, finalized).value
  assert sameChainView(restored, fixture.view)
  assert sameStateSnapshot(restored.finalizedBlock.value.stateSnapshot,
      finalized.value.stateSnapshot)
  assert restored.blockAt(finalized.value.blockHash).error == GenesisError.None
  assert restored.retainedBlockAt(RetainedBlockIndex(-1)).error == GenesisError.Unavailable
  assert restored.retainedBlockAt(RetainedBlockIndex(MaxRetainedBlocks)).error ==
      GenesisError.Unavailable
  assert restoreLocalChainView([]).error == ViewAdvanceError.InvalidSnapshot
  var oversized = retained
  oversized.add(finalized)
  assert restoreLocalChainView(oversized, finalized).error == ViewAdvanceError.InvalidSnapshot
  let duplicate = [retained[0], retained[0]]
  assert restoreLocalChainView(duplicate).error == ViewAdvanceError.Duplicate
  let reversed = [retained[1], retained[0]]
  assert restoreLocalChainView(reversed).error == ViewAdvanceError.NotChild
  assert restoreLocalChainView(retained, fixture.blocks[1]).error == ViewAdvanceError.None
  let inside = retained[2]
  let selected = restoreLocalChainView(retained, inside).value
  assert sameStateSnapshot(selected.finalizedBlock.value.stateSnapshot,
    selected.blockAt(inside.value.blockHash).value.stateSnapshot)
  # Header/root-equal independently reconstructed state cannot replace an in-window finalized owner.
  let original = inside.value
  let state = original.stateSnapshot
  var entries: seq[StateEntry] = @[]
  for index in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: state.lookup(key).value.bytes))
  let detached = newStateStore(entries, fixture.policy).value.snapshot.value
  var wire = newSeq[byte](original.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(original.header, wire).error == HeaderError.None
  let foreign = captureBlockSnapshot(wire, detached, original.chainParameters)
  assert restoreLocalChainView(retained, foreign).error == ViewAdvanceError.InvalidSnapshot
  assert sameChainView(fixture.view, restored)
proc policyWitness() {.raises.} =
  ## Count accepted owners rather than slots; windows and immutable finality survive independent forks.
  let fixture = diskHistoryFixture(16, true, ElementLimit(32))
  let original = fixture.view
  assert original.retainedCount == 17
  assert uint64(original.retentionLimit) == 32
  for capacity in [1, 3, 8, 12]:
    let selected = original.withRetentionLimit(ElementLimit(capacity)).value
    assert selected.retainedCount == capacity
    assert uint64(selected.retentionLimit) == uint64(capacity)
    assert sameStateSnapshot(selected.bestBlock.value.stateSnapshot,
        original.bestBlock.value.stateSnapshot)
    assert sameStateSnapshot(selected.finalizedBlock.value.stateSnapshot,
        original.finalizedBlock.value.stateSnapshot)
    for index in 0..<capacity:
      assert sameStateSnapshot(selected.retainedBlockAt(RetainedBlockIndex(
          index)).value.stateSnapshot,
        fixture.blocks[fixture.blocks.len-capacity+index].value.stateSnapshot)
    let enlarged = selected.withRetentionLimit(ElementLimit(32)).value
    assert enlarged.retainedCount == capacity # Expansion grants future capacity without backfill.
    assert not sameChainView(enlarged, selected)
    assert original.retainedCount == 17 # The source owner and every retained historical map survive.
  let last = fixture.blocks[^1]
  let seed = genesisView(fixture.blocks[0], ElementLimit(1))
  let gap = genesisView(fixture.blocks[^2], ElementLimit(1)).advanceView(last).value
  assert gap.retainedCount == 1 and seed.retainedCount == 1
  let wide = restoreLocalChainView(fixture.blocks, original.finalizedBlock, ElementLimit(32)).value
  assert sameChainView(wide, original)
  assert original.withRetentionLimit(ElementLimit(0)).error == ViewAdvanceError.InvalidSnapshot
  assert original.withRetentionLimit(ElementLimit(high(uint64))).error ==
      ViewAdvanceError.InvalidSnapshot
  assert genesisView(last, ElementLimit(0)).retainedCount == 0
  let absent = default(ChainView)
  assert absent.withRetentionLimit(ElementLimit(1)).error == ViewAdvanceError.Uninitialized
  # Linked appends enforce the configured suffix while preserving a finalized owner outside it.
  for capacity in [1, 3, 12]:
    let rolling = diskHistoryFixture(16, true, ElementLimit(capacity)).view
    assert rolling.retainedCount == capacity
    assert rolling.finalizedBlock.error == GenesisError.None
    assert rolling.blockAt(rolling.finalizedBlock.value.blockHash).error == GenesisError.None
    assert rolling.blockAt(fixture.blocks[1].value.blockHash).error == GenesisError.Unavailable
try:
  main()
  policyWitness()
except:
  quit(2) # Fixture failures cannot become passing local-history reconstruction.
echo "PASS local history restoration: bounded suffix, evicted finality and exact in-window owners"
