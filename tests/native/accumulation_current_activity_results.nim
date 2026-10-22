# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current C13 exposes neither partial activity nor inactive child causes.
import std/cmdline
import ../../src/state/[accumulation_current_activity, accumulation_activity,
    accumulation_current_validators]
let owner = default(CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity])
let activity = default(PreparedCurrentAccumulationActivity)
let refused = prepareCurrentAccumulationActivity(default(PreparedCurrentAccumulationValidators),
    default(AccumulationActivityConfig))
case paramStr(1)
of "refused": discard refused.value # No successful prefix after source refusal.
of "source": discard activity.currentActivitySource.value # No fabricated validator source.
of "preimages": discard activity.currentActivityPreimages.value # No fabricated original-parent admission.
of "info": discard activity.currentActivityInfo.value # No partial union observations.
of "snapshot": discard activity.currentActivitySnapshot.value # No default initialized activity.
of "entry": discard activity.currentActivityEntry.value # No synthetic complete C13 wire.
of "state": discard activity.currentActivityState.value # No complete map after refusal.
of "preimage-reason": discard refused.preimageError # Require real selected preimage refusal.
of "core-reason": discard refused.coreError # Require real selected core/service refusal.
of "codec-reason": discard refused.codecError # Require real selected codec refusal.
of "state-reason": discard refused.stateError # Require real selected private-store refusal.
else: discard owner.value # Default tagged result remains uninitialized.
