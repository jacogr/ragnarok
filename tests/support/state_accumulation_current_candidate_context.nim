# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current candidate policies reuse maintained signed-block admission and complete current execution/state ceilings.
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded
import ./state_accumulation_execution_context
import ./state_accumulation_current_completion_context
import ./state_report_admission_context as reports
proc currentCandidateLimits*(): CurrentCandidateLimits =
  ## All resource groups remain explicit; no source-derived protocol facts are replaced.
  CurrentCandidateLimits(reporting: reports.transitionConfig(), queue: executionQueueConfig(),
    round: executionRoundConfig(), completion: currentCompletionLimits(), headerBytes: ByteLimit(100000))
