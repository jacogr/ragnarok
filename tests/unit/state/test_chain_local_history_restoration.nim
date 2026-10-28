# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local restoration preserves evicted and in-window finality under exact map ownership.
import std/assertions
import std/syncio
import ../../support/storage_disk_history_context
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_trie as codec_state_trie
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
try:
  main()
except:
  quit(2) # Fixture failures cannot become passing local-history reconstruction.
echo "PASS local history restoration: bounded suffix, evicted finality and exact in-window owners"
