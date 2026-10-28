# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial verified proof evidence cannot be published as a complete StateStore snapshot.
# @@Verification={"group":"nominal","expected":"StateStoreSnapshot","early":["preparePagedState(","[1] expected: StateStoreSnapshot but got: ProofView"]}
import ../../../src/state/paged_state as state_paged_state
import ../../../src/state/proof_view as state_proof_view
discard preparePagedState(default(ProofView), [], default(PagedStateLimits))
