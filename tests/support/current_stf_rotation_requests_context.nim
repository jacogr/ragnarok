# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit regular/exceptional request-fact capture supports reservation cleanup and incarnation replacement.
import ./current_stf_rotation_code_context
import ../../src/app/candidate
import ../../src/codec/bounded

proc rotationRequestLimits*(): CurrentCandidateLimits =
  ## One identity may be touched before/after checkpoints; four bounded facts preserve both effect versions.
  result = rotationCodeLimits()
  result.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  result.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
