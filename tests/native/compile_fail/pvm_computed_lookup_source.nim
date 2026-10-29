# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject substituted source, byte policy or dictionary index as ancestor authority.

# @@Verification={"group": "nominal", "expected": "RecentComputedReport", "early": ["checkComputedLookupAnchor(", "[1] expected: RecentComputedReport but got: StateBoundComputedReport"]}

import ../../../src/state/computed/[lookup as computed_lookup, recent as computed_recent,
    state as computed_state]
import ../../../src/state/report/identity as report_identity
import ../../../src/codec/bounded
discard checkComputedLookupAnchor(default(StateBoundComputedReport), [], default(ComputedLookupLimits))
