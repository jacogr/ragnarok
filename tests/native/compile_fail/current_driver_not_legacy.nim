# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedBlockAccumulation but got: CompletedCurrentAccumulationSequence", "early": ["executionInfo(", "[1] expected: CompletedBlockAccumulation but got: CompletedCurrentAccumulationSequence"]}

## Terminal current sequence and initial/legacy whole-block owners carry distinct authority.
import ../../../src/state/[accumulation_current_driver, accumulation_execution]
discard executionInfo(default(CompletedCurrentAccumulationSequence))
