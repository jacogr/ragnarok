# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict extraction probes keep default/refused round completions from exposing data or parent reasons.

import std/cmdline
import ../../src/state/accumulation/[execution as accumulation_execution,
    round as accumulation_round, inputs as accumulation_inputs]

let argument = paramStr(1)
let owner = default(CompletedBlockAccumulation)
let result = if argument == "default": default(AccumulationExecutionResult[CompletedBlockAccumulation])
  else: completeBlockAccumulation(default(BlockAccumulationRound), [], [], default(
      AccumulationExecutionLimits))
case argument
of "info": discard owner.executionInfo.value # No fabricated budget or actual gas total.
of "gas": discard owner.executionGasAt(InvocationServiceIndex(0)).value # No fabricated zero row.
of "batch": discard owner.executionBatch.value # No usable batch accompanies a default completion.
of "round": discard owner.executionRound.value # No default can impersonate admitted provenance.
of "wrong-batch": discard result.batchFailure # InvalidRound is not a selected batch refusal.
else: discard result.value # Both default and invalid-round alternatives refuse extraction.
