# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationAccounts but got: CompletedCurrentAccumulationSequence", "early": ["prepareCurrentAccumulationFinalization(", "[1] expected: PreparedCurrentAccumulationAccounts but got: CompletedCurrentAccumulationSequence"]}

## Current timestamp provenance cannot be replaced with another completion domain.
import ../../../src/state/[accumulation_current_finalization, accumulation_current_driver]
discard prepareCurrentAccumulationFinalization(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationFinalizationConfig))
