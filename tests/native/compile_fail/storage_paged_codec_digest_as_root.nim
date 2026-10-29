# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local integrity, protocol roots, byte offsets and page ordinals retain distinct nominal roles.
# @@Verification={"group":"nominal","expected":"StateRoot","early":["initPagedHeader(","[2] expected: StateRoot but got: PagedDigest"]}
import ../../../src/storage/paged/codec as paged_codec
import ../../../src/storage/database_identity
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/light/delta as light_delta
import ../../../src/codec/state/trie as state_trie
discard initPagedHeader(default(StorageChainId), default(PagedDigest), ManagedEpoch(1),
    LightDeltaSequence(0), 0, 0, PagedLimits())
