# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected default/refused chain results expose neither children nor unselected phase causes.

import std/cmdline
import ../../src/chain/[provider, genesis]
import ../../src/state/[accumulation_chain, accumulation_finalization, accumulation_completion, store]

let argument = paramStr(1)
var state = default(StateStore)
var view = default(ChainView)
let outcome = if argument == "default": default(AccumulationChainResult)
  else: applyAccumulationChain(state, view, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits))
case argument
of "parameters":
  let absent = default(BlockSnapshot)
  discard absent.chainParameters # A default chain owner cannot supply an apparently usable protocol tuple.
of "state": discard outcome.stateError # Invalid source authorizes no target snapshot lookup.
of "application": discard outcome.applicationFailure # No private state application was selected.
of "header": discard outcome.headerError # No admitted header was inspected.
of "capture": discard outcome.captureError # No child capture was attempted.
of "view": discard outcome.viewError # No chain append was attempted.
else: discard outcome.value # Neither default nor refused source contains a published child.
