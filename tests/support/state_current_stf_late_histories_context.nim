# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded C15 capacity for longer executable histories; all protocol facts and production defaults remain source-derived.
import ./state_current_stf_late_retention_context
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded

proc lateHistoryLimits*(): CurrentCandidateLimits =
  ## Seventeen retained hashes exceed the original thirteen;24 still fits the existing1024-byte ring budget.
  result = lateRetentionLimits()
  result.completion.composition.finalization.history.queues.totalItems = ElementLimit(24)
