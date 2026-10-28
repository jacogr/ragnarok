# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded operand/history capacity for zero-gas skips draining deferred reports beside fresh work.
import ./state_current_stf_rotation_incarnations_context
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded

proc lateRetentionLimits*(): CurrentCandidateLimits =
  ## Seven reports can finish in five prefixes; preserve every other qualified incarnation limit and production default.
  result = rotationIncarnationLimits()
  result.completion.composition.statistics.operands = ElementLimit(8)
  result.completion.composition.finalization.history.reports = ElementLimit(8)
  result.completion.composition.finalization.history.queues.perSlot = ElementLimit(8)
  # Zero-charge serial prefixes require five genuine facts and five provider visits, independent of operand totals.
  result.completion.execution.execution.entries = ElementLimit(8)
  result.completion.composition.statistics.entries = ElementLimit(8)
  result.completion.composition.finalization.outputs.entries = ElementLimit(8)
  result.completion.composition.finalization.outputs.outcomes = ElementLimit(8)
