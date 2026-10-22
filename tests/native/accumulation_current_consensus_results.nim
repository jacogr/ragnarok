# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused consensus owners reveal no source, observations or partially composed map.
import std/cmdline
import ../../src/state/[accumulation_current_consensus, accumulation_consensus,
    accumulation_current_authorization]
let owner = default(CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus])
let consensus = default(PreparedCurrentAccumulationConsensus)
let refused = prepareCurrentAccumulationConsensus(default(PreparedCurrentAccumulationAuthorization),
    default(AccumulationConsensusLimits))
case paramStr(1)
of "refused": discard refused.value # Source refusal exposes no candidate prefix.
of "source": discard consensus.currentConsensusSource.value # No fabricated pool advancement.
of "info": discard consensus.currentConsensusInfo.value # No fake slot or copy extents.
of "state": discard consensus.currentConsensusState.value # No partial composed map.
of "backend": discard refused.stateError # Require an actual selected store refusal.
else: discard owner.value # Default tagged result remains uninitialized.
