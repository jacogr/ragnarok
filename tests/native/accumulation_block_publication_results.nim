# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Publication failures/defaults contain no adopted snapshot or unselected store cause.

import std/cmdline
import ../../src/state/[accumulation_block_publication, accumulation_consensus, store]

let argument = paramStr(1)
var state = default(StateStore)
let outcome = if argument == "default": default(AccumulationPublicationResult)
  else: publishAccumulationState(state, default(PreparedAccumulationConsensus))
case argument
of "wrong-state": discard outcome.stateError # StateFailure is not selected after an invalid source.
else: discard outcome.value # Defaults and refused sources cannot expose a successful snapshot.
