# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused bound preimage results expose neither partial owners nor unselected child causes.

import std/cmdline
import ../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../src/state/accumulation_activity as state_accumulation_activity

let argument = paramStr(1)
let owner = default(PreparedAccumulationPreimages)
let outcome = if argument == "default": default(AccumulationPreimageResult[PreparedAccumulationPreimages])
  else: prepareAccumulationPreimages(default(PreparedAccumulationActivity), default(
      AccumulationPreimageLimits))
case argument
of "source": discard owner.accumulationPreimagesSource.value # No substituted activity certificate.
of "info": discard owner.accumulationPreimagesInfo.value # No default admitted populations or slot.
of "state": discard owner.accumulationPreimagesState.value # No partial complete-map successor.
of "wrong-preimage": discard outcome.preimageError # PreimageFailure is not selected.
else: discard outcome.value # Default and refused alternatives carry reasons alone.
