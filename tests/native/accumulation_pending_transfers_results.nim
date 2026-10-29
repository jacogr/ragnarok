# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic strict guards for pending ownership, first-entry absence and selected nested partition reasons.
import std/[cmdline, syncio]
import ../../src/state/accumulation/[pending_transfers as accumulation_pending_transfers,
    transfer_partition as accumulation_transfer_partition, transfers as accumulation_transfers]
import ../../src/state/store
import ../../src/codec/[bounded, composite]
import ../../src/codec/state/[accounts as state_accounts, trie as state_trie]

proc empty(): PreparedPendingTransfers =
  ## Validate real positive setup before any deliberate invalid extraction.
  let source = prepareAccumulationTransfers([], default(AccumulationTransferCollectionLimits))
  if source.error != AccumulationTransferCollectionError.None: quit(3)
  let prepared = prepareInitialPendingTransfers(source.value, Gas(0), default(PendingTransferLimits))
  if prepared.error != PendingTransferError.None: quit(4)
  prepared.value
proc state(): StateStoreSnapshot =
  ## An unexpected fixture failure must never satisfy a selected-result guard.
  let created = newStateStore([], StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(16),
      perValue: ByteLimit(256), totalValueBytes: ByteLimit(4096), nodes: TrieNodeLimit(1000))))
  if created.error != StateStoreError.None: quit(5)
  let snapshot = created.value.snapshot
  if snapshot.error != StateStoreError.None: quit(6)
  snapshot.value
let outcome = if paramStr(1) == "refused":
  prepareInitialPendingTransfers(default(PreparedAccumulationTransfers), Gas(0), default(PendingTransferLimits))
else: default(PendingTransferResult[PreparedPendingTransfers]) # Dynamic alternatives contain no pending queue.
let plan = default(PreparedPendingTransfers)
case paramStr(1)
of "default", "refused": discard outcome.value
of "info": discard plan.pendingTransferInfo.value
of "record": discard plan.pendingTransferAt(PendingTransferIndex(0)).value
of "outgoing": discard plan.pendingOutgoing.value
of "previous": discard plan.pendingPreviousPartition.value
of "first-previous": discard empty().pendingPreviousPartition.value # Initialized first entry is still NoPrevious.
of "index": discard empty().pendingTransferAt(PendingTransferIndex(high(
    uint64))).value # Initialized empty queues still reject invalid ordinals.
of "partition-value":
  let failed = empty().partitionPendingTransfers(default(StateStoreSnapshot), [], default(TransferPartitionLimits))
  discard failed.value # Actual nested failure cannot expose a successful partition.
of "reason": discard outcome.partitionError # Default/refused success result has no selected nested reason.
of "reason-success":
  let succeeded = empty().partitionPendingTransfers(state(), [], default(TransferPartitionLimits))
  discard succeeded.partitionError # Successful child contains no partition-failure reason.
else: quit(2)
