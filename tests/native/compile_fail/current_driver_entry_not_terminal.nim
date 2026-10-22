# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedCurrentAccumulationSequence but got: PreparedCurrentAccumulationRound"}

## Terminal current sequence and initial/legacy whole-block owners carry distinct authority.
import ../../../src/state/[accumulation_current_driver, accumulation_current_round]
discard completedSequenceInfo(default(PreparedCurrentAccumulationRound))
