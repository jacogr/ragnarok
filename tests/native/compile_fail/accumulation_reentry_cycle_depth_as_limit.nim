# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationReentryDepthLimit", "early": ["prepareAccumulationReentry(", "[3] expected: AccumulationReentryDepthLimit but got: AccumulationReentryDepth"]}

## Reject mixing report/depth observations with the explicit recursion policy limit.

import ../../../src/state/accumulation/reentry as accumulation_reentry
var completed: CompletedAccumulationReentry
discard prepareAccumulationReentry(completed, default(AccumulationReentryConfig),
    AccumulationReentryDepth(2))
