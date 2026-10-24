# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local integrity, protocol roots, byte offsets and page ordinals retain distinct nominal roles.
# @@Verification={"group":"nominal","expected":"StateRoot","early":["initPagedHeader(","[2] expected: StateRoot but got: PagedDigest"]}
import ../../../src/storage/[paged_codec, database_identity, managed_manifest, light_delta]
import ../../../src/codec/state_trie
discard initPagedHeader(default(StorageChainId), default(PagedDigest), ManagedEpoch(1),
    LightDeltaSequence(0), 0, 0, PagedLimits())
