# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationProvisionStage but got: PreparedAccumulationProvisionPhase", "early": ["prepareAccumulationGlobalStage(", "[1] expected: PreparedAccumulationProvisionStage but got: PreparedAccumulationProvisionPhase"]}

## Pure selected state cannot replace authenticated initial-stage ownership.
import ../../../src/state/accumulation/global/stage as accumulation_global_stage
import ../../../src/state/accumulation/provision/phase as accumulation_provision_phase
import ../../../src/state/accumulation/provisions as accumulation_provisions
discard prepareAccumulationGlobalStage(default(PreparedAccumulationProvisionPhase), default(AccumulationGlobalStageLimits))
