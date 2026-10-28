# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A borrowed immutable light image may not violate its compiler-enforced mutability or owner lifetime.
# @@Verification={"group": "ownership_compile", "build_name": "storage-light-view-escape", "expected": "cannot borrow from encodedBytes(local)"}
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc escaped(): lent seq[byte] =
  let local = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
      LightSnapshotLimits(bytes: ByteLimit(128))).value
  local.encodedBytes
discard escaped().len
