# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused prepared current updates expose no immutable candidate or inactive child failure.
import std/cmdline
import ../../src/chain/provider
import ../../src/codec/bounded
import ../../src/state/[accumulation_current_update, accumulation_current_consensus, store]
let result = default(CurrentChainPreparationResult)
let owner = default(PreparedCurrentChainUpdate)
var state = default(StateStore)
var view = default(ChainView)
let refused = prepareCurrentChainUpdate(state, view, default(PreparedCurrentAccumulationConsensus),
    ByteLimit(0))
case paramStr(1)
of "refused": discard refused.value # No successful private prefix after coordinator refusal.
of "reason": discard result.chainFailure # Require an actual selected failed coordinator.
of "state": discard owner.currentUpdateState # Require initialized opaque preparation.
of "view": discard owner.currentUpdateView # Require initialized complete view.
of "child": discard owner.currentUpdateChild # Require initialized captured child.
of "install": installCurrentChainUpdate(state, view,
    owner) # Default readiness cannot authorize target replacement.
else: discard result.value # Default tagged result remains uninitialized.
