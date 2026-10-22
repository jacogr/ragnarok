# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Complete provider ownership and result storage stay private.
import ../../../src/state/[accumulation_coverage, accumulation_annulment]
import ../../../src/codec/header
let refused = prepareAccumulationCoverage(default(PreparedAccumulationAnnulment), [], [],
    HeaderSlot(0), default(AccumulationCoverageLimits))
discard refused.completed
