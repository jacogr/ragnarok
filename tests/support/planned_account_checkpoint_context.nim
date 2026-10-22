# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit restoration and complete audit policies avoid unsupported nested-constant field folding.
import ./[account_audit_plan_context, state_inventory_context]
import ../../src/state/[planned_account_checkpoint, validated_checkpoint, store, global_snapshot]
import ../../src/codec/[bounded, state_composition]
const plannedCheckpointTestLimits* = PlannedAccountCheckpointLimits(
  serialization: StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: inventoryMapLimits, writes: ElementLimit(64),
        writeValueBytes: ByteLimit(262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: inventoryManifestLimits),
  inventory: inventoryCaptureLimits, audit: accountAuditTestLimits)
