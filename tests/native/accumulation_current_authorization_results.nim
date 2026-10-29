# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current pool owners expose no earlier source, encoding, map or inactive cause.
import std/cmdline
import ../../src/state/accumulation/current/authorization as accumulation_current_authorization
import ../../src/state/accumulation/authorization as accumulation_authorization
import ../../src/state/accumulation/current/preimages as accumulation_current_preimages
let owner = default(CurrentAccumulationAuthorizationResult[
    PreparedCurrentAccumulationAuthorization])
let pools = default(PreparedCurrentAccumulationAuthorization)
let refused = prepareCurrentAccumulationAuthorization(default(PreparedCurrentAccumulationPreimages),
    default(AccumulationAuthorizationLimits))
case paramStr(1)
of "refused": discard refused.value # No successful source prefix after refusal.
of "source": discard pools.currentAuthorizationSource.value # No fabricated current fulfillment.
of "info": discard pools.currentAuthorizationInfo.value # No synthetic core/slot observations.
of "entry": discard pools.currentAuthorizationEntry.value # No default initialized pool encoding.
of "state": discard pools.currentAuthorizationState.value # No partial complete map.
of "codec": discard refused.codecError # Require actual selected codec failure.
of "authorization": discard refused.authorizationError # Require actual selected pure transition failure.
of "backend": discard refused.stateError # Require actual selected private-store failure.
else: discard owner.value # Default tagged result remains uninitialized.
