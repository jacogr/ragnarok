# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "roleReason"}

## No writable tag or inactive global phase payload is public.
import ../../../src/state/accumulation_global_stage as state_accumulation_global_stage
import ../../../src/state/accumulation_provision_stage as state_accumulation_provision_stage
let refused = prepareAccumulationGlobalStage(default(PreparedAccumulationProvisionStage), default(
    AccumulationGlobalStageLimits))
discard refused.roleReason
