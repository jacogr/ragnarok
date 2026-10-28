# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ContinuationReportIndex", "early": ["reentryReportAt(", "[2] expected: ContinuationReportIndex but got: InvocationServiceIndex"]}

## Reject substitution of nominal reentry source/report domains.

import ../../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
var plan: PreparedAccumulationReentry
discard reentryReportAt(plan, InvocationServiceIndex(0))
