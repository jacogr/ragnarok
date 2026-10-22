# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current chain coordination exposes no child or inactive nested stage reason.
import std/cmdline
import ../../src/chain/provider
import ../../src/codec/bounded
import ../../src/state/[accumulation_current_chain, accumulation_current_consensus, store]
let owner = default(CurrentAccumulationChainResult)
var state = default(StateStore)
var view = default(ChainView)
let refused = applyCurrentAccumulationChain(state, view, default(
    PreparedCurrentAccumulationConsensus), ByteLimit(0))
case paramStr(1)
of "refused": discard refused.value # No successful private prefix after source refusal.
of "state": discard refused.stateError # Require actual selected target refusal.
of "publication": discard refused.publicationFailure # Require actual selected private adoption refusal.
of "header": discard refused.headerError # Require actual selected header refusal.
of "capture": discard refused.captureError # Require actual selected capture refusal.
of "view": discard refused.viewError # Require actual selected view refusal.
else: discard owner.value # Default tagged result remains uninitialized.
