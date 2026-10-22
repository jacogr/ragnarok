# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused absence alternatives cannot expose state, input/slot observations or block authority.
import std/cmdline
import ../../src/state/[accumulation_absent, accumulation_inputs, store]
import ../../src/codec/header
let argument = paramStr(1)
let owner = default(AbsentAccumulation)
let refused = if argument == "default": default(AccumulationAbsentResult[AbsentAccumulation])
  else: finishAbsentAccumulation(default(PreparedAccumulationInputs), InvocationServiceIndex(0),
      default(StateStoreSnapshot), HeaderSlot(0))
case argument
of "info": discard owner.absentInfo.value # No false zero-gas observations.
of "state": discard owner.absentState.value # No false identity map.
of "inputs": discard owner.absentInputs.value # No substitute input owner.
of "index": discard owner.absentIndex.value # No detached valid ordinal.
of "round": discard default(BlockAbsentAccumulation).absentBlockRound.value # No false admitted provenance.
of "projection": discard default(BlockAbsentAccumulation).absentProjection.value # No false pure no-execution certificate.
else: discard refused.value # Failure carries reasons alone.
