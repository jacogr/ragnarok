# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw integer cannot impersonate the dense computed-availability report ordinal.

# @@Verification={"group": "nominal", "expected": "ComputedAvailableIndex", "early": ["computedAssuredReportAt(", "[2] expected: ComputedAvailableIndex but got: int"]}

import ../../../src/state/computed_assurances as state_computed_assurances
let ordinal = 1
discard computedAssuredReportAt(default(AssuredComputedReports), ordinal)
