# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationAccountStage but got: PreparedAccumulationAccountPhase", "early": ["prepareAccumulationProvisionStage(", "[1] expected: PreparedAccumulationAccountStage but got: PreparedAccumulationAccountPhase"]}

## Pure selected state cannot replace authenticated initial-stage ownership.
import ../../../src/state/accumulation/provision/stage as accumulation_provision_stage
import ../../../src/state/accumulation/account/phase as accumulation_account_phase
import ../../../src/state/accumulation/provisions as accumulation_provisions
discard prepareAccumulationProvisionStage(default(PreparedAccumulationAccountPhase), default(AccumulationProvisionUnionLimits))
