# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit nine-member staging copies and retained ancestor proofs for four-epoch designation histories.
import ./current_stf_rotation_hosts_context
import ../../src/app/candidate
import ../../src/codec/bounded

proc rotationDesignationLimits*(): CurrentCandidateLimits =
  ## Three queues7680 + staging3025 + privilege25 bytes need10730; twenty headers cover eighteen transitions.
  result = rotationHostLimits()
  result.completion.execution.initial.guests.contexts.totalBytes = ByteLimit(11000)
  result.completion.execution.execution.round.guests.contexts.totalBytes = ByteLimit(11000)
  result.reporting.reports.ancestors.headers = ElementLimit(20)
  result.reporting.reports.ancestors.maxBytes = ByteLimit(32768)
