# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached profile, snapshot, stage or copied facts as authenticated computed provenance.

# @@Verification={"group": "nominal", "expected": "TransitionBoundComputedReport", "early": ["checkComputedRoster(", "[1] expected: TransitionBoundComputedReport but got: BlockTransitionResult"]}

import ../../../src/state/computed/[roster as computed_roster, transition as computed_transition,
    profile as computed_profile]
import "../../../src/state/block/transition" as block_transition
import ../../../src/state/store
discard checkComputedRoster(default(BlockTransitionResult), ComputedRosterLimits())
