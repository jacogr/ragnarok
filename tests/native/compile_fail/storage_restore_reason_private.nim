# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed standalone reconstruction reasons are private and success guarded.
# @@Verification={"group":"privacy","expected":"trieReason"}
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/full_state_trie as storage_full_state_trie
let hidden = default(RepositoryResult[FullStateTrie])
discard hidden.trieReason
