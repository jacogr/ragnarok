# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Borrowed delta bytes may neither mutate immutable authority nor outlive their local owner.
# @@Verification={"group": "ownership_compile", "build_name": "storage-light-delta-view-escape", "expected": "cannot borrow from encodedBytes(local)"}
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
let before = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
    LightSnapshotLimits(bytes: ByteLimit(128))).value
let bounds = LightDeltaLimits(bytes: ByteLimit(208))
proc escaped(): lent seq[byte] =
  let local = prepareLightDelta(before, LightDeltaSequence(1), [], [], bounds).value
  local.encodedBytes
discard escaped().len
