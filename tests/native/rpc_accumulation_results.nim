# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and closed-listener publication results expose no child or unselected adoption failure.

import std/cmdline
import ../../src/rpc/server as rpc_server
import ../../src/state/store as state_store
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/state/accumulation_completion as state_accumulation_completion

let argument = paramStr(1)
var owner = default(Server)
var state = default(StateStore)
let outcome = if argument == "default": default(RpcAccumulationResult)
  else: owner.publishAccumulation(state, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits))
if argument == "chain":
  discard outcome.chainFailure # Unavailable listeners authorize no state/chain work or nested failure payload.
else:
  discard outcome.value # Default and closed-listener alternatives contain no usable child.
