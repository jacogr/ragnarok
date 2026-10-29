# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local integrity, protocol roots, byte offsets and page ordinals retain distinct nominal roles.
# @@Verification={"group":"nominal","expected":"PageOrdinal","early":["pagedPath(","[2] expected: PageOrdinal but got: PagedOffset"]}
import ../../../src/storage/paged/codec as paged_codec
import ../../../src/storage/database_identity
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/light/delta as light_delta
import ../../../src/codec/state/trie as state_trie
discard pagedPath(default(PagedGeometry), PagedOffset(0))
