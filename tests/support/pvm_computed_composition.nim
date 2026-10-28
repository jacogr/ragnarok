# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual finalized computed work with canonical original statistics and bounded maintained state-composition policies.

import ./pvm_computed_storage_program
import ../../src/state/computed_finalization as state_computed_finalization
import ../../src/state/accumulation_completion as state_accumulation_completion
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ./pvm_computed_finalization
import ./state_accumulation_completion_context

proc compositionFixture*(withComposition = true, withChain = false,
    storage = ComputedStorageMode.Disabled): FinalizedComputedAccumulation =
  ## Author original statistics before computation, then genuinely execute and stop the historical work.
  let source = finalizationFixture(withComposition = withComposition, withChain = withChain,
      storage = storage)
  finalizeComputedAccumulation(source, computedFinalizationConfig()).value
proc computedCompositionLimits*(): AccumulationCompositionLimits =
  ## Adapt only the actual three-core domains and independent aggregate reporter/queue resource ceilings.
  result = completionLimits().composition
  result.history.queues.cores = CoreCount(3)
  result.ready.queues.cores = CoreCount(3)
  result.recent.history.cores = CoreCount(3)
  result.validators.validators = ElementLimit(9)
  result.validators.projection.reporters = ElementLimit(9)
  result.validators.projection.comparisons = ElementLimit(128)
  result.authorization.inputHashes = ElementLimit(512)
