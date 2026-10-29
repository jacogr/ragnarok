# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused source-bound authorization cannot expose partial sources, encodings, maps or unselected causes.

import std/cmdline
import ../../src/state/accumulation/[authorization as accumulation_authorization,
    preimages as accumulation_preimages]

let argument = paramStr(1)
let owner = default(PreparedAccumulationAuthorization)
let outcome = if argument == "default": default(AccumulationAuthorizationResult[PreparedAccumulationAuthorization])
  else: prepareAccumulationAuthorization(default(PreparedAccumulationPreimages), default(
      AccumulationAuthorizationLimits))
case argument
of "source": discard owner.accumulationAuthorizationSource.value # No substituted preimage candidate.
of "info": discard owner.accumulationAuthorizationInfo.value # No invented slot or core count.
of "entry": discard owner.accumulationAuthorizationEntry.value # No partial canonical encoding.
of "state": discard owner.accumulationAuthorizationState.value # No fabricated full-map successor.
of "wrong-codec": discard outcome.codecError # CodecFailure is not selected.
of "wrong-authorization": discard outcome.authorizationError # AuthorizationFailure is not selected.
of "wrong-state": discard outcome.stateError # StateFailure is not selected.
else: discard outcome.value # Default/refused alternatives carry reasons alone.
