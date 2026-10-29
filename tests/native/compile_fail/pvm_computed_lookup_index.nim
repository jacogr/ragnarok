# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject substituted source, byte policy or dictionary index as ancestor authority.

# @@Verification={"group": "nominal", "expected": "ComputedAncestorIndex", "early": ["computedLookupHeader(", "[2] expected: ComputedAncestorIndex but got: ReportLookupIndex"]}

import ../../../src/state/computed/[lookup as computed_lookup, recent as computed_recent,
    state as computed_state]
import ../../../src/state/report/identity as report_identity
import ../../../src/codec/bounded
discard computedLookupHeader(default(LookupAnchoredComputedReport), ReportLookupIndex(0))
