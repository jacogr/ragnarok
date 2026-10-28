# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationReentryDepthLimit", "early": ["prepareAccumulationReentry(", "[3] expected: AccumulationReentryDepthLimit but got: AccumulationReportPrefix"]}

## Reject mixing report/depth observations with the explicit recursion policy limit.

import ../../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../../src/state/accumulation_operands as state_accumulation_operands
var completed: CompletedAccumulationReentry
discard prepareAccumulationReentry(completed, default(AccumulationReentryConfig),
    AccumulationReportPrefix(2))
