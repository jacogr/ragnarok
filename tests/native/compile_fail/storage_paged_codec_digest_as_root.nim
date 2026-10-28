# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local integrity, protocol roots, byte offsets and page ordinals retain distinct nominal roles.
# @@Verification={"group":"nominal","expected":"StateRoot","early":["initPagedHeader(","[2] expected: StateRoot but got: PagedDigest"]}
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/codec/state_trie as codec_state_trie
discard initPagedHeader(default(StorageChainId), default(PagedDigest), ManagedEpoch(1),
    LightDeltaSequence(0), 0, 0, PagedLimits())
