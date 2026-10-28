# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current recent-history predecessors distinguish processed reports from newly guaranteed reports.
import ../../src/codec/report_owned as codec_report_owned
import ../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../src/state/accumulation_current_finalization as state_accumulation_current_finalization
import ../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ./state_accumulation_current_outputs_context
import ./state_accumulation_current_finalization_context
import ./state_accumulation_current_driver_context
import ./state_accumulation_current_round_context
import ./state_accumulation_execution_context
import ./state_accumulation_ready_witnesses
proc currentRecentReady*(base: OwnedReport, incoming = false): PreparedCurrentAccumulationReady =
  ## Process a queued report, or include a genuine new guarantee without making it available in the same block.
  var completed: CompletedCurrentAccumulationSequence
  if incoming:
    var options = executionFixtureConfig()
    options.signed.reports = 1
    let fixture = executionFixture(base, options)
    completed = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(),
        currentSequenceDriverLimits()).value
  else:
    completed = currentOutputCompletion(base, false) # Later processed original work must not become a newly guaranteed package.
  let accounts = currentFinalizationAccounts(completed)
  let finalized = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig()).value
  prepareCurrentAccumulationReady(finalized, readyPolicy()).value
