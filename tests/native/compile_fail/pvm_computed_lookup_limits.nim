# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject substituted source, byte policy or dictionary index as ancestor authority.

# @@Verification={"group": "nominal", "expected": "ComputedLookupLimits", "early": ["checkComputedLookupAnchor(", "[3] expected: ComputedLookupLimits but got: ByteLimit"]}

import ../../../src/state/computed/[lookup as computed_lookup, recent as computed_recent,
    state as computed_state]
import ../../../src/state/report/identity as report_identity
import ../../../src/codec/bounded
discard checkComputedLookupAnchor(default(RecentComputedReport), [], ByteLimit(1000))
