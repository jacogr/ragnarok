# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current publication cannot expose an adopted map or inactive store cause.
import std/cmdline
import ../../src/state/accumulation/current/[publication as accumulation_current_publication,
    consensus as accumulation_current_consensus]
import ../../src/state/store
let owner = default(CurrentAccumulationPublicationResult)
var state = default(StateStore)
let refused = publishCurrentAccumulationState(state, default(PreparedCurrentAccumulationConsensus))
case paramStr(1)
of "refused": discard refused.value # No candidate after source refusal.
of "backend": discard refused.stateError # Require actual selected store failure.
else: discard owner.value # Default tagged result remains uninitialized.
