# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached profile, snapshot, stage or copied facts as authenticated computed provenance.

# @@Verification={"group": "nominal", "expected": "TransitionBoundComputedReport", "early": ["checkComputedRoster(", "[1] expected: TransitionBoundComputedReport but got: ConfiguredComputedReport"]}

import ../../../src/state/[computed_roster, computed_transition, computed_profile, block_transition, store]
discard checkComputedRoster(default(ConfiguredComputedReport), ComputedRosterLimits())
