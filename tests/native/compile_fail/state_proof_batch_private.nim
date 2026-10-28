# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate or mutate proof/lookup authority.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/trie_proof as state_trie_proof
let owner = default(VerifiedStateProofBatch)
discard owner.data
