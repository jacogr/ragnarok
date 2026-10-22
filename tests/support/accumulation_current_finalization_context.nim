# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared current terminal finalization policies retain genuine statistics and timestamp ownership.
import ../../src/codec/[bounded, assurances, state_workqueues]
import ../../src/state/[accumulation_current_finalization, accumulation_history,
  accumulation_current_accounts, accumulation_accounts, accumulation_current_statistics,
  accumulation_current_driver]
import ./[accumulation_current_outputs_context, accumulation_current_statistics_context]
proc currentFinalizationConfig*(): CurrentAccumulationFinalizationConfig =
  ## Match the authenticated two-core/twelve-slot profile and one processed package.
  CurrentAccumulationFinalizationConfig(outputs: currentOutputLimits(),
    history: AccumulationHistoryConfig(reports: ElementLimit(4), queues: WorkQueueConfig(
      cores: CoreCount(2), epochSlots: EpochSlots(12), perSlot: ElementLimit(4),
      totalItems: ElementLimit(8), maxBytes: ByteLimit(1024))))
proc currentFinalizationAccounts*(completed: CompletedCurrentAccumulationSequence): PreparedCurrentAccumulationAccounts =
  ## Only real current statistics authorize metadata writes and the finalization input.
  let statistics = prepareCurrentAccumulationStatistics(completed, currentStatisticsLimits()).value
  prepareCurrentAccumulationAccounts(statistics,
    AccumulationAccountConfig(services: ElementLimit(4), metadataBytes: ByteLimit(420))).value
