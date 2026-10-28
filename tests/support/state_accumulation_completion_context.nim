# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit tiny-profile resource policies for stopped driver completion and independently authored phase chains.

import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/state_history as codec_state_history
import ../../src/codec/state_outputs as codec_state_outputs
import ../../src/pvm/step as pvm_step
import ../../src/state/accumulation_completion as state_accumulation_completion
import ../../src/state/accumulation_driver as state_accumulation_driver
import ../../src/state/accumulation_runner as state_accumulation_runner
import ../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../src/state/accumulation_history as state_accumulation_history
import ../../src/state/accumulation_ready as state_accumulation_ready
import ../../src/state/accumulation_recent as state_accumulation_recent
import ../../src/state/accumulation_times as state_accumulation_times
import ../../src/state/accumulation_statistics as state_accumulation_statistics
import ../../src/state/accumulation_activity as state_accumulation_activity
import ../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../src/state/accumulation_consensus as state_accumulation_consensus
import ./state_accumulation_execution_context
import ./state_accumulation_runner_context
import ./state_accumulation_activity_context

proc completionLimits*(): AccumulationCompletionLimits =
  ## Every phase keeps an independent bounded policy; populations come from the actual source profile.
  let outputs = OutputLogConfig(items: ElementLimit(16), maxBytes: ByteLimit(1000))
  AccumulationCompletionLimits(
    finalization: AccumulationOutputHistoryLimits(rounds: ElementLimit(8), executions: ElementLimit(
        16), log: outputs),
    composition: AccumulationCompositionLimits(history: AccumulationHistoryConfig(
        reports: ElementLimit(8), queues: executionQueueConfig(
    ).queues),
    ready: AccumulationReadyConfig(items: ElementLimit(128), dependencies: ElementLimit(1024),
        queues: executionQueueConfig().queues),
    recent: AccumulationRecentConfig(headerBytes: ByteLimit(4096), outputs: outputs,
      history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(
          8), totalPackages: ElementLimit(32), peaks: ElementLimit(10), maxBytes: ByteLimit(
          10000))),
    times: AccumulationTimesConfig(statistics: AccumulationStatisticsLimits(rounds: ElementLimit(8),
        gasRows: ElementLimit(16), reports: ElementLimit(8), digests: ElementLimit(16),
        services: ElementLimit(4)),
      accounts: AccumulationTimesLimits(services: ElementLimit(4), writes: ElementLimit(4),
          bytes: ByteLimit(356))),
    validators: activityValidatorConfig(),
    activity: AccumulationActivityConfig(componentBytes: ByteLimit(4096),
      preimages: PreimageLimits(items: ElementLimit(4), perBlob: ByteLimit(16),
          totalBlobBytes: ByteLimit(32)),
      incoming: ElementLimit(8), available: ElementLimit(8), digests: ElementLimit(16),
          assurances: ElementLimit(8), provisions: ElementLimit(4), accumulation: ElementLimit(4),
          services: ElementLimit(4), activityBytes: ByteLimit(10000)),
    preimages: AccumulationPreimageLimits(items: ElementLimit(4), bytes: ByteLimit(32)),
    authorization: AccumulationAuthorizationLimits(guarantees: ElementLimit(8),
        inputHashes: ElementLimit(160), inputBytes: ByteLimit(10000), outputHashes: ElementLimit(
        32), outputBytes: ByteLimit(2000)),
    consensus: AccumulationConsensusLimits(chapterBytes: ByteLimit(10000), totalBytes: ByteLimit(50000))))

proc completionDriverLimits*(): AccumulationDriverLimits =
  ## Bounded policies cover both idle continuations and the authored seven-report reentry history.
  var execution = runnerLimits()
  execution.fetch.items = ElementLimit(8)
  execution.fetch.bytes = ByteLimit(10000)
  execution.steps = ExecutionStepLimit(100)
  execution.calls = HostCallLimit(16)
  AccumulationDriverLimits(preparation: AccumulationReentryConfig(
    selection: AccumulationContinuationLimits(executions: ElementLimit(4), reports: ElementLimit(
        16), digests: ElementLimit(32)),
    operands: executionRoundConfig().operands, inputs: executionRoundConfig().inputs),
    execution: execution, depth: AccumulationReentryDepthLimit(8))
