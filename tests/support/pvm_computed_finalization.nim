# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine completed computed service execution and bounded stopped-history/finalization policies.

import std/[assertions, syncio]
import ./pvm_computed_storage_program
import ../../src/state/[computed_execution, computed_finalization, accumulation_driver,
  accumulation_runner, accumulation_dispatch, accumulation_execution, accumulation_batch,
  accumulation_reentry, accumulation_continuation, accumulation_outputs]
import ../../src/codec/[bounded, state_outputs]
import ../../src/pvm/step
import ./[pvm_computed_execution, accumulation_execution_context]

proc finalizationFixture*(withReady = true, withComposition = false,
    withChain = false, storage = ComputedStorageMode.Disabled): ExecutedComputedAccumulation =
  ## Execute the actual selected guest before any stopped-history/final-state construction.
  var limits = computedExecutionLimits()
  if storage != ComputedStorageMode.Disabled:
    # Local provenance admits one self key; only original wide-fetch guests retain eleven bytes including the full returned word.
    limits.accountWriteKeys = ElementLimit(1)
    limits.completion.batch.selfWrites = ElementLimit(1)
    let bytes = if storage in {ComputedStorageMode.FetchWideOffset,
        ComputedStorageMode.FetchWideIndex, ComputedStorageMode.FetchTail}: 11'u64 else: 3'u64
    limits.completion.batch.selfValueBytes = ByteLimit(bytes)
  if storage == ComputedStorageMode.FetchReadBack:
    limits.steps = ExecutionStepLimit(32) # Admit only the new24-instruction read-after-write guest before its original execution.
  let executed = executeComputedAccumulation(computedExecutionFixture(withReady = withReady,
      withComposition = withComposition, withChain = withChain, storage = storage), limits)
  if executed.error != ComputedExecutionError.None:
    echo "computed execution ", executed.error
    if executed.error == ComputedExecutionError.RunnerFailure:
      let runner = executed.runnerFailure
      echo "runner ", runner.error
      if runner.error == AccumulationRunnerError.DispatchFailure: echo "dispatch ",
          runner.dispatchFailure.error
      if runner.error == AccumulationRunnerError.CompletionFailure:
        echo "completion ", runner.completionFailure.error
        if runner.completionFailure.error == AccumulationExecutionError.BatchFailure: echo "batch ",
            runner.completionFailure.batchFailure.error
  assert executed.error == ComputedExecutionError.None
  executed.value
proc computedFinalizationConfig*(): ComputedFinalizationConfig =
  ## Only an idle continuation is needed for this exhausted queue; retained history still counts both actual rounds.
  ComputedFinalizationConfig(driver: AccumulationDriverLimits(
    preparation: AccumulationReentryConfig(selection: AccumulationContinuationLimits(
      executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
      operands: executionRoundConfig().operands, inputs: executionRoundConfig().inputs),
    execution: computedExecutionLimits(), depth: AccumulationReentryDepthLimit(0)),
    outputs: AccumulationOutputHistoryLimits(rounds: ElementLimit(2), executions: ElementLimit(1),
      log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1))))
