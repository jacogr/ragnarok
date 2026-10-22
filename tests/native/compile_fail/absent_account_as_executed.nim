# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: AccumulationOutcome but got: AbsentAccumulation"}

## Absent outcomes cannot alias protocol service ordinals or actual executed outcomes.
import ../../../src/state/[accumulation_absent, accumulation_inputs, accumulation_outcome, store]
import ../../../src/codec/[header, state_accounts]
discard outcomeInfo(default(AbsentAccumulation))
