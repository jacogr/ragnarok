# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached profile, snapshot, stage or copied facts as authenticated computed provenance.

# @@Verification={"group": "nominal", "expected": "TransitionBoundComputedReport", "early": ["checkComputedRoster(", "[1] expected: TransitionBoundComputedReport but got: StateStoreSnapshot"]}

import ../../../src/state/computed_roster as state_computed_roster
import ../../../src/state/computed_transition as state_computed_transition
import ../../../src/state/computed_profile as state_computed_profile
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/store as state_store
discard checkComputedRoster(default(StateStoreSnapshot), ComputedRosterLimits())
