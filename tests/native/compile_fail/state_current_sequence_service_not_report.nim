# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CurrentPlanReportIndex but got: InvocationServiceIndex", "early": ["currentContinuationReportAt(", "[2] expected: CurrentPlanReportIndex but got: InvocationServiceIndex"]}

## Current source owners and plan-local ordinal domains cannot substitute one another.
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
discard currentContinuationReportAt(default(PreparedCurrentContinuation), InvocationServiceIndex(0))
