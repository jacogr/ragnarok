# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact one-halt-code provision budget extends lifecycle qualification without changing its prior profile.
import ./[current_stf_rotation_lifecycle_context, pvm_accumulation_provision]
import ../../src/app/candidate
import ../../src/codec/[bounded, composite]

proc rotationCodeLimits*(): CurrentCandidateLimits =
  ## One actual29-byte target and its encoded union have finite independent capture/integration ceilings.
  result = rotationLifecycleLimits()
  result.completion.execution.initial.guests.provisions = provisionPolicy(items = 1, perBlob = 29, total = 29)
  result.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
      perBlob: ByteLimit(29), totalBlobBytes: ByteLimit(29))
  result.completion.execution.initial.provisions.encodedBytes = ByteLimit(64)
  result.completion.execution.execution.round.guests.provisions = result.completion.execution.initial.guests.provisions
  result.completion.execution.execution.round.provisions = result.completion.execution.initial.provisions
