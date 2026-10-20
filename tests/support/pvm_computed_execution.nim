# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real multi-entry original service code and three-core context policies for computed accumulation execution.

import ./pvm_computed_storage_program
import ../../src/state/[computed_round, accumulation_runner]
import ../../src/codec/[assurances, bounded, c2_records]
import ./[pvm_computed_round, accumulation_runner_context, pvm_accumulation_context]

proc computedExecutionFixture*(withReady = true, withExecution = true,
    invalidEntry = false, withComposition = false, withChain = false,
        storage = ComputedStorageMode.Disabled): ComputedAccumulationRound =
  ## Author original code/queues before root/signing/computation, then derive the genuine selected round.
  let source = roundFixture(withReady = withReady, withExecution = withExecution,
      invalidEntry = invalidEntry, withComposition = withComposition, withChain = withChain,
      storage = storage)
  prepareComputedRound(source, computedRoundConfig(source)).value
proc computedExecutionLimits*(): AccumulationRunnerLimits =
  ## Match authenticated three-core context while independently bounding service/input/engine capture.
  result = runnerLimits()
  result.contexts = pvmContextConfig(3)
  result.contexts.validators = ValidatorCount(9)
  result.fetch.operand = OperandLimits(outputBytes: ByteLimit(1000), authBytes: ByteLimit(1000),
    totalBlobBytes: ByteLimit(2000), maxBytes: ByteLimit(4000))
  result.fetch.bytes = ByteLimit(10000)
