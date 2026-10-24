# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local integrity, protocol roots, byte offsets and page ordinals retain distinct nominal roles.
# @@Verification={"group":"nominal","expected":"PageOrdinal","early":["pagedPath(","[2] expected: PageOrdinal but got: PagedOffset"]}
import ../../../src/storage/[paged_codec, database_identity, managed_manifest, light_delta]
import ../../../src/codec/state_trie
discard pagedPath(default(PagedGeometry), PagedOffset(0))
