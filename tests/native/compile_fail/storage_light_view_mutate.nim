# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A borrowed immutable light image may not violate its compiler-enforced mutability or owner lifetime.
# @@Verification={"group": "ownership_compile", "build_name": "storage-light-view-mutate", "expected": "cannot pass encodedBytes(snapshot) to var/out T parameter"}
import ../../../src/storage/light/snapshot as light_snapshot
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc mutate(snapshot: PreparedLightSnapshot) =
  snapshot.encodedBytes[0] = 1
let snapshot = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
    LightSnapshotLimits(bytes: ByteLimit(128))).value
mutate(snapshot)
