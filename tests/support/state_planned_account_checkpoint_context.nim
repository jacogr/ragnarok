# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit restoration and complete audit policies avoid unsupported nested-constant field folding.
import ./state_account_audit_plan_context
import ./state_inventory_context
import ../../src/state/planned_account_checkpoint as state_planned_account_checkpoint
import ../../src/state/validated_checkpoint as state_validated_checkpoint
import ../../src/state/store as state_store
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_composition as codec_state_composition
const plannedCheckpointTestLimits* = PlannedAccountCheckpointLimits(
  serialization: StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: inventoryMapLimits, writes: ElementLimit(64),
        writeValueBytes: ByteLimit(262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: inventoryManifestLimits),
  inventory: inventoryCaptureLimits, audit: accountAuditTestLimits)
