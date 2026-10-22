# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused global phases expose no inactive owner, component or failure payload.
import std/cmdline
import ../../src/state/[accumulation_global_stage, accumulation_provision_stage]
let owner = default(AccumulationGlobalStageResult[PreparedAccumulationGlobalStage])
let refused = prepareAccumulationGlobalStage(default(PreparedAccumulationProvisionStage), default(
    AccumulationGlobalStageLimits))
let stage = default(PreparedAccumulationGlobalStage)
case paramStr(1)
of "refused": discard refused.value # Only this actual selected variant permits extraction.
of "role": discard owner.roleFailure # Only this actual selected variant permits extraction.
of "queue": discard owner.queueFailure # Only this actual selected variant permits extraction.
of "staging": discard owner.stagingFailure # Only this actual selected variant permits extraction.
of "store": discard owner.storeFailure # Only this actual selected variant permits extraction.
of "info": discard stage.globalStageInfo.value # Only this actual selected variant permits extraction.
of "provisions": discard stage.globalStageProvisions.value # Only this actual selected variant permits extraction.
of "roles": discard stage.globalStageRoles.value # Only this actual selected variant permits extraction.
of "snapshot": discard stage.globalStageSnapshot.value # Only this actual selected variant permits extraction.
else: discard owner.value # No fabricated complete global phase.
