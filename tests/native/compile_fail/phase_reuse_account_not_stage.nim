# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationAccountStage but got: PreparedAccumulationAccountPhase"}

## Pure selected state cannot replace authenticated initial-stage ownership.
import ../../../src/state/[accumulation_provision_stage, accumulation_account_phase, accumulation_provisions]
discard prepareAccumulationProvisionStage(default(PreparedAccumulationAccountPhase), default(AccumulationProvisionUnionLimits))
