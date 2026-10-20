# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached state, loose tables or incomplete computed provenance.

# @@Verification={"group": "nominal", "expected": "RosterEligibleComputedReport", "early": ["prepareComputedGuarantors(", "[1] expected: RosterEligibleComputedReport but got: StateStoreSnapshot"]}

import ../../../src/state/[computed_guarantors, computed_roster, computed_transition, guarantors, store]
discard prepareComputedGuarantors(default(StateStoreSnapshot), ComputedGuarantorLimits())
