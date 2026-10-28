# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic strict extraction probes distinguish default/refused plans and invalid initialized output ordinals.
import std/cmdline
import std/syncio
import ../../src/state/accumulation_transfer_partition as state_accumulation_transfer_partition
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie

let outcome = if paramStr(1) == "refused":
  prepareAccumulationTransferPartition(default(StateStoreSnapshot), [], [], default(TransferPartitionLimits))
else: default(TransferPartitionResult[PreparedTransferPartition]) # Neither dynamic alternative supplies a plan.
let plan = default(PreparedTransferPartition)
case paramStr(1)
of "default", "refused": discard outcome.value # Refusals expose no plan payload.
of "info": discard plan.partitionInfo.value # Defaults expose no successful counts.
of "prior": discard plan.partitionPrior.value # Defaults expose no prior owner.
of "count": discard plan.partitionCount(TransferPartitionKind.Accepted).value # Defaults cannot fabricate an empty output.
of "transfer": discard plan.partitionTransferAt(TransferPartitionKind.Accepted,
    TransferPartitionIndex(0)).value # Defaults expose no record.
of "index":
  let created = newStateStore([], StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(16),
      perValue: ByteLimit(256), totalValueBytes: ByteLimit(4096), nodes: TrieNodeLimit(1000))))
  if created.error != StateStoreError.None: quit(3) # Fixture refusal must not masquerade as the intended partition guard.
  let source = created.value.snapshot
  if source.error != StateStoreError.None: quit(4)
  let prepared = prepareAccumulationTransferPartition(source.value, [], [], default(TransferPartitionLimits))
  if prepared.error != TransferPartitionError.None: quit(5)
  let initialized = prepared.value
  discard initialized.partitionTransferAt(TransferPartitionKind.Accepted, TransferPartitionIndex(
      high(uint64))).value # Initialized empty plans still reject full-width invalid ordinals.
else: quit(2)
