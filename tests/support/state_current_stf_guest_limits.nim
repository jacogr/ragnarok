# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit current STF fetch, statistics and code-blob ceilings preserve every existing authored guest profile.
import ./state_current_consecutive_context
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded
proc currentStfGuestLimits*(): CurrentCandidateLimits =
  ## Return the original common body/trace guest policy; callers independently declare lifecycle-specific resource ceilings.
  var limits = currentConsecutiveLimits()
  limits.completion.composition.validators.projection.assurances = ElementLimit(6)
  limits.completion.composition.validators.projection.reporters = ElementLimit(6)
  limits.completion.composition.validators.projection.comparisons = ElementLimit(36)
  limits.completion.composition.activity.available = ElementLimit(2)
  limits.completion.composition.activity.assurances = ElementLimit(6)
  # Two real report operands carry five-byte authorization traces and two-byte successful outputs.
  limits.completion.execution.initial.guests.fetch.items = ElementLimit(2)
  limits.completion.execution.initial.guests.fetch.bytes = ByteLimit(1024)
  limits.completion.execution.initial.guests.fetch.operand.outputBytes = ByteLimit(2)
  limits.completion.execution.initial.guests.fetch.operand.authBytes = ByteLimit(5)
  limits.completion.execution.initial.guests.fetch.operand.totalBlobBytes = ByteLimit(7)
  # Continuation dispatch captures the same bounded report payloads after the first affordable prefix.
  limits.completion.execution.execution.round.guests.fetch = limits.completion.execution.initial.guests.fetch
  # One release resolves five authored reports across two batches, all retained in one processed row.
  limits.completion.composition.statistics.operands = ElementLimit(5)
  limits.completion.composition.finalization.history.reports = ElementLimit(5)
  limits.completion.composition.finalization.history.queues.perSlot = ElementLimit(5)
  # Whole guest-code preimages retain explicit byte limits independent of operand payload bounds.
  limits.completion.composition.validators.preimageBytes = ByteLimit(512)
  limits.completion.composition.activity.preimages.perBlob = ByteLimit(512)
  limits.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(512)
  limits.completion.composition.preimages.bytes = ByteLimit(512)
  limits
