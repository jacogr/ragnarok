# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused ready owners cannot expose an earlier source, encoded ring or inactive child reasons.
import std/cmdline
import ../../src/state/accumulation/current/ready as accumulation_current_ready
import ../../src/state/accumulation/ready as accumulation_ready
import ../../src/state/accumulation/current/finalization as accumulation_current_finalization
let owner = default(CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady])
let ready = default(PreparedCurrentAccumulationReady)
let refused = prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationFinalization),
    default(AccumulationReadyConfig))
case paramStr(1)
of "refused": discard refused.value # Source refusal exposes no map prefix.
of "source": discard ready.currentReadySource.value # No fabricated finalization.
of "ring": discard ready.currentReadyRing.value # No default empty ring.
of "state": discard ready.currentReadyState.value # No synthetic selected map.
of "entry": discard ready.currentReadyEntry.value # No default initialized encoding.
of "codec": discard refused.codecFailure # Only real parent decoder refusal exposes this reason.
of "projection": discard refused.projectionFailure # Only real pure projection refusal exposes this reason.
of "backend": discard refused.stateFailure # Only real private-store refusal exposes this reason.
else: discard owner.value # Default tagged result remains uninitialized.
