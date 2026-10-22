# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current candidate policies reuse maintained signed-block admission and complete current execution/state ceilings.
import ../../src/app/candidate
import ../../src/codec/bounded
import ./[accumulation_execution_context, accumulation_current_completion_context]
import ./report_admission_context as reports
proc currentCandidateLimits*(): CurrentCandidateLimits =
  ## All resource groups remain explicit; no source-derived protocol facts are replaced.
  CurrentCandidateLimits(reporting: reports.transitionConfig(), queue: executionQueueConfig(),
    round: executionRoundConfig(), completion: currentCompletionLimits(), headerBytes: ByteLimit(100000))
