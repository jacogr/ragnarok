# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full native complete maps cannot substitute for the separate light proof database.
# @@Verification={"group":"nominal","expected":"PagedReader","early":["readPagedProofView(","[1] expected: PagedReader but got: FullPagedReader"]}
import ../../../src/state/paged_proof_view as state_paged_proof_view
import ../../../src/storage/full_paged_store as storage_full_paged_store
import ../../../src/codec/state_trie as codec_state_trie
var reader = default(FullPagedReader)
discard readPagedProofView(reader, default(StateRoot), [], default(PagedProofViewLimits))
