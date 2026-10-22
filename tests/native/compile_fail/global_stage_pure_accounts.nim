# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationProvisionStage but got: PreparedAccumulationAccountStage", "early": ["prepareAccumulationGlobalStage(", "[1] expected: PreparedAccumulationProvisionStage but got: PreparedAccumulationAccountStage"]}

## Account state alone cannot bypass complete original provision fulfillment.
import ../../../src/state/[accumulation_global_stage, accumulation_account_stage]
discard prepareAccumulationGlobalStage(default(PreparedAccumulationAccountStage), default(AccumulationGlobalStageLimits))
