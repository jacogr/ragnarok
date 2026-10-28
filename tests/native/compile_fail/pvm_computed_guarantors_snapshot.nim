# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached state, loose tables or incomplete computed provenance.

# @@Verification={"group": "nominal", "expected": "RosterEligibleComputedReport", "early": ["prepareComputedGuarantors(", "[1] expected: RosterEligibleComputedReport but got: StateStoreSnapshot"]}

import ../../../src/state/computed_guarantors as state_computed_guarantors
import ../../../src/state/computed_roster as state_computed_roster
import ../../../src/state/computed_transition as state_computed_transition
import ../../../src/state/guarantors as state_guarantors
import ../../../src/state/store as state_store
discard prepareComputedGuarantors(default(StateStoreSnapshot), ComputedGuarantorLimits())
