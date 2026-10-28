# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded foreign-write code provision supports actual supervisor retirement and recreation.
import ./state_current_stf_rotation_requests_context
import ./pvm_accumulation_provision
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite

proc rotationIncarnationLimits*(): CurrentCandidateLimits =
  ## One supplied replacement program fits512 bytes; both regular and checkpoint versions keep the same policy.
  result = rotationRequestLimits()
  result.completion.execution.initial.guests.provisions = provisionPolicy(items = 1, perBlob = 512, total = 512)
  result.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
      perBlob: ByteLimit(512), totalBlobBytes: ByteLimit(512))
  result.completion.execution.initial.provisions.encodedBytes = ByteLimit(1024)
  result.completion.execution.execution.round.guests.provisions = result.completion.execution.initial.guests.provisions
  result.completion.execution.execution.round.provisions = result.completion.execution.initial.provisions
