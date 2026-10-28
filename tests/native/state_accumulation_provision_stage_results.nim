# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## No inactive provision phase payload may escape default or refused preparation.
import std/cmdline
import ../../src/state/accumulation_provision_stage as state_accumulation_provision_stage
import ../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../src/state/accumulation_account_stage as state_accumulation_account_stage
let owner = default(AccumulationProvisionStageResult[PreparedAccumulationProvisionStage])
let refused = prepareAccumulationProvisionStage(default(PreparedAccumulationAccountStage), default(
    AccumulationProvisionUnionLimits))
let stage = default(PreparedAccumulationProvisionStage)
case paramStr(1)
of "refused": discard refused.value # Selected success is required for this exact alternative.
of "provision": discard owner.provisionFailure # Selected success is required for this exact alternative.
of "store": discard owner.storeFailure # Selected success is required for this exact alternative.
of "accounts": discard stage.provisionStageAccounts.value # Selected success is required for this exact alternative.
of "plan": discard stage.provisionStagePlan.value # Selected success is required for this exact alternative.
of "snapshot": discard stage.provisionStageSnapshot.value # Selected success is required for this exact alternative.
else: discard owner.value # No fabricated fulfilled map.
