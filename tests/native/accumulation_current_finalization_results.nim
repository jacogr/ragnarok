# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current finalization exposes neither a map prefix nor inactive child reasons.
import std/cmdline
import ../../src/state/accumulation/current/[finalization as accumulation_current_finalization,
    accounts as accumulation_current_accounts]
let owner = default(CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization])
let finalized = default(PreparedCurrentAccumulationFinalization)
let refused = prepareCurrentAccumulationFinalization(default(PreparedCurrentAccumulationAccounts),
    default(CurrentAccumulationFinalizationConfig))
case paramStr(1)
of "refused": discard refused.value # No successful source prefix after refusal.
of "info": discard finalized.currentFinalizationInfo.value # No default progress.
of "accounts": discard finalized.currentFinalizationAccounts.value # No synthetic timestamps.
of "outputs": discard finalized.currentFinalizationOutputs.value # No synthetic terminal pair union.
of "history": discard finalized.currentFinalizationHistory.value # No synthetic ring.
of "state": discard finalized.currentFinalizationState.value # No synthetic complete selected map.
of "output-reason": discard refused.outputFailure # Require actual failed output union.
of "queue-reason": discard refused.queueFailure # Require actual failed C15 capture.
of "projection-reason": discard refused.projectionFailure # Require actual failed pure projection.
of "state-reason": discard refused.stateFailure # Require actual failed private apply.
else: discard owner.value # Default remains uninitialized.
