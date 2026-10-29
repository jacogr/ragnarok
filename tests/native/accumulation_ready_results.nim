# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default or refused ready-queue results cannot expose projections, maps or unrelated failure reasons.

import std/cmdline
import ../../src/state/accumulation/[ready as accumulation_ready, history as accumulation_history]
import ../../src/codec/state/workqueues as state_workqueues
import ../../src/codec/header

let argument = paramStr(1)
let owner = default(PreparedAccumulationReady)
let outcome = if argument == "default": default(AccumulationReadyResult[PreparedAccumulationReady])
  else: prepareAccumulationReady(default(PreparedAccumulationHistory), default(
      AccumulationReadyConfig))
case argument
of "projection":
  discard projectAccumulationReady(default(ReadySnapshot), default(AccumulatedSnapshot), [], [],
    HeaderSlot(0), HeaderSlot(1), default(AccumulationReadyConfig)).value # A missing input owner never yields an initialized projection.
of "source": discard owner.accumulationReadySource.value # No fabricated finalization.
of "ring": discard owner.accumulationReadyRing.value # No fabricated complete ready ring.
of "state": discard owner.accumulationReadyState.value # No fabricated full-state candidate.
of "entry": discard owner.accumulationReadyEntry.value # No fabricated canonical bytes.
of "wrong-codec": discard outcome.codecError # InvalidSource/default is not a selected codec refusal.
of "wrong-state": discard outcome.stateError # InvalidSource/default is not a selected state refusal.
else: discard outcome.value # Defaults and refused candidates carry reasons alone.
