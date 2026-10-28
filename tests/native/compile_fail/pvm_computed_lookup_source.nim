# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject substituted source, byte policy or dictionary index as ancestor authority.

# @@Verification={"group": "nominal", "expected": "RecentComputedReport", "early": ["checkComputedLookupAnchor(", "[1] expected: RecentComputedReport but got: StateBoundComputedReport"]}

import ../../../src/state/computed_lookup as state_computed_lookup
import ../../../src/state/computed_recent as state_computed_recent
import ../../../src/state/computed_state as state_computed_state
import ../../../src/state/report_identity as state_report_identity
import ../../../src/codec/bounded as codec_bounded
discard checkComputedLookupAnchor(default(StateBoundComputedReport), [], default(ComputedLookupLimits))
