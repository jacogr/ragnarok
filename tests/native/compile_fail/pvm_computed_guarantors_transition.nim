# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached state, loose tables or incomplete computed provenance.

# @@Verification={"group": "nominal", "expected": "RosterEligibleComputedReport", "early": ["prepareComputedGuarantors(", "[1] expected: RosterEligibleComputedReport but got: TransitionBoundComputedReport"]}

import ../../../src/state/computed/[guarantors as computed_guarantors, roster as computed_roster,
    transition as computed_transition]
import ../../../src/state/[guarantors, store]
discard prepareComputedGuarantors(default(TransitionBoundComputedReport), ComputedGuarantorLimits())
