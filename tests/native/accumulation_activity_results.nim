# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused combined activity cannot expose sources, preimage admission, encoded rows, snapshots or unselected failure causes.

import std/cmdline
import ../../src/state/[accumulation_activity, accumulation_validators]

let argument = paramStr(1)
let owner = default(PreparedAccumulationActivity)
let outcome = if argument == "default": default(AccumulationActivityResult[PreparedAccumulationActivity])
  else: prepareAccumulationActivity(default(PreparedAccumulationValidators), default(
      AccumulationActivityConfig))
case argument
of "source": discard owner.accumulationActivitySource.value # No fabricated validator certificate.
of "preimages": discard owner.accumulationActivityPreimages.value # No disconnected original-parent admission.
of "info": discard owner.accumulationActivityInfo.value # No stale traversal populations.
of "snapshot": discard owner.accumulationActivitySnapshot.value # No fabricated empty complete activity.
of "entry": discard owner.accumulationActivityEntry.value # No partial canonical encoding.
of "state": discard owner.accumulationActivityState.value # No partial complete-map successor.
of "wrong-preimage": discard outcome.preimageError # PreimageFailure is not selected.
of "wrong-core": discard outcome.coreError # CoreFailure is not selected.
of "wrong-codec": discard outcome.codecError # CodecFailure is not selected.
of "wrong-state": discard outcome.stateError # StateFailure is not selected.
else: discard outcome.value # Failed/default alternatives carry reasons alone.
