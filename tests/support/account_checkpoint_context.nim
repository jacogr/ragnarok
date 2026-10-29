# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit restoration and invariant policies support unchanged-format checkpoint consumer fixtures.
import ./[state_inventory_context, account_invariant_context]
import ../../src/state/account/checkpoint as account_checkpoint
import ../../src/state/[validated_checkpoint, store, global_snapshot]
import ../../src/codec/bounded
import ../../src/codec/state/composition as state_composition
const accountCheckpointLimits* = AccountCheckpointLimits(
  serialization: StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: inventoryMapLimits, writes: ElementLimit(64),
        writeValueBytes: ByteLimit(262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: inventoryManifestLimits),
  inventory: inventoryCaptureLimits, footprints: invariantFootprintLimits,
  content: invariantContentLimits, linkage: invariantLinkageLimits)
