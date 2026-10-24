# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Borrowed delta bytes may neither mutate immutable authority nor outlive their local owner.
# @@Verification={"group": "ownership_compile", "build_name": "storage-light-delta-view-mutate", "expected": "cannot pass encodedBytes(delta) to var/out T parameter"}
import ../../../src/storage/[light_delta, light_snapshot, database_identity]
import ../../../src/codec/[bounded, state_trie]
let before = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
    LightSnapshotLimits(bytes: ByteLimit(128))).value
let bounds = LightDeltaLimits(bytes: ByteLimit(208))
let local = prepareLightDelta(before, LightDeltaSequence(1), [], [], bounds).value
proc mutate(delta: PreparedLightDelta) =
  delta.encodedBytes[0] = 1
mutate(local)
