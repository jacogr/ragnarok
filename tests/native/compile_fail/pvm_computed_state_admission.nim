# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached transcript or map as completed provenance.

# @@Verification={"group": "nominal", "expected": "BlockAdmissionResult", "early": ["bindComputedState(", "[2] expected: BlockAdmissionResult but got: StateStoreSnapshot"]}

import ../../../src/state/computed_state as state_computed_state
import ../../../src/state/computed_links as state_computed_links
import ../../../src/state/computed_guarantee as state_computed_guarantee
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
discard bindComputedState(default(ComputedReportLinks), default(StateStoreSnapshot))
