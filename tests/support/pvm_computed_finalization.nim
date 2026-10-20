# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine completed computed service execution and bounded stopped-history/finalization policies.

import ../../src/state/[computed_execution, computed_finalization, accumulation_driver,
  accumulation_reentry, accumulation_continuation, accumulation_outputs]
import ../../src/codec/[bounded, state_outputs]
import ./[pvm_computed_execution, accumulation_execution_context]

proc finalizationFixture*(withReady = true, withComposition = false,
    withChain = false): ExecutedComputedAccumulation =
  ## Execute the actual selected guest before any stopped-history/final-state construction.
  executeComputedAccumulation(computedExecutionFixture(withReady = withReady,
      withComposition = withComposition, withChain = withChain), computedExecutionLimits()).value
proc computedFinalizationConfig*(): ComputedFinalizationConfig =
  ## Only an idle continuation is needed for this exhausted queue; retained history still counts both actual rounds.
  ComputedFinalizationConfig(driver: AccumulationDriverLimits(
    preparation: AccumulationReentryConfig(selection: AccumulationContinuationLimits(
      executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
      operands: executionRoundConfig().operands, inputs: executionRoundConfig().inputs),
    execution: computedExecutionLimits(), depth: AccumulationReentryDepthLimit(0)),
    outputs: AccumulationOutputHistoryLimits(rounds: ElementLimit(2), executions: ElementLimit(1),
      log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1))))
