# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared live-graph root selection preserves rolling validation snapshots and independently selected finality.
## Historical record files are self-contained and never expand this paged/managed live-root inventory.
import ../chain
import ../../chain/[genesis, provider]
import ../../state/store
import ../../storage/history/index as history_index

proc liveDiskSources*(owner: ApplicationChain): HistoryResult[seq[StateStoreSnapshot]] =
  ## Return exact inherited-policy owners oldest-first, with current last and external finality included once.
  let current = owner.stateSnapshot
  let view = owner.chainView
  if current.error != StateStoreError.None or view.retainedCount == 0 or view.hasHistoricalIndex:
    return historyFailure[seq[StateStoreSnapshot]](HistoryError.StaleSelection)
  var sources: seq[StateStoreSnapshot] = @[]
  let finalized = view.finalizedBlock
  var inside = false
  if finalized.error == GenesisError.None:
    for index in 0..<view.retainedCount:
      if array[32, byte](view.retainedBlockAt(RetainedBlockIndex(index)).value.blockHash) ==
          array[32, byte](finalized.value.blockHash): inside = true
    if not inside: sources.add(finalized.value.stateSnapshot)
  for index in 0..<view.retainedCount:
    sources.add(view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot)
  for source in sources:
    if not sameStateStorePolicy(current.value, source):
      return historyFailure[seq[StateStoreSnapshot]](HistoryError.StaleSelection)
  historySuccess(sources)
