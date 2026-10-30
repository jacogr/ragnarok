# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A borrowed immutable light image may not violate its compiler-enforced mutability or owner lifetime.
# @@Verification={"group":"ownership_compile","build_name":"storage-light-view-escape","expected":"cannot borrow from encodedBytes(local)","rationale":"Returning encoded snapshot bytes borrowed from a local prepared snapshot would leave replay/checkpoint consumers holding a dangling buffer after the owner dies.","reference":"src/storage/light/snapshot.nim"}
import ../../../src/storage/light/snapshot as light_snapshot
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc escaped(): lent seq[byte] =
  let local = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
      LightSnapshotLimits(bytes: ByteLimit(128))).value
  local.encodedBytes
discard escaped().len
