# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reusable phases retain private result payloads independently of authenticated wrappers.
import ../../../src/state/[accumulation_account_phase, accumulation_provision_phase,
    accumulation_global_phase, accumulation_coverage, accumulation_provisions]
let refused = prepareAccumulationAccountPhase(default(PreparedAccumulationCoverage), default(
    AccumulationAccountPhaseLimits))
discard refused.completed
