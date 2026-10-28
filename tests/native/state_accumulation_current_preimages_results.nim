# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current preimage owners cannot expose source, partial fulfilled maps or inactive causes.
import std/cmdline
import ../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
import ../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../src/state/accumulation_current_activity as state_accumulation_current_activity
let owner = default(CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages])
let preimages = default(PreparedCurrentAccumulationPreimages)
let refused = prepareCurrentAccumulationPreimages(default(PreparedCurrentAccumulationActivity),
    default(AccumulationPreimageLimits))
case paramStr(1)
of "refused": discard refused.value # No previous successful stage after source refusal.
of "source": discard preimages.currentPreimagesSource.value # No fabricated current C13 source.
of "info": discard preimages.currentPreimagesInfo.value # No synthetic admitted count or slot.
of "state": discard preimages.currentPreimagesState.value # No partial fulfilled map.
of "preimage-reason": discard refused.preimageError # Only selected real integration failure permits this cause.
else: discard owner.value # Default tagged result remains uninitialized.
