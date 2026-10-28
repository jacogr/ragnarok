# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded large-code/copy policy for literal privilege guests across changing rosters.
import ./state_current_stf_population_reporting_context
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded
import ../../src/pvm/initialize as pvm_initialize
import ../../src/pvm/machine as pvm_machine

proc rotationHostLimits*(): CurrentCandidateLimits =
  ## A real eighty-hash queue needs2560 copied bytes and a complete4096-byte code envelope.
  result = populationReportingLimits()
  result.completion.composition.validators.preimageBytes = ByteLimit(4096)
  result.completion.composition.activity.preimages.perBlob = ByteLimit(4096)
  result.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(4096)
  result.completion.composition.preimages.bytes = ByteLimit(4096)
  result.completion.execution.initial.guests.preimageBytes = ByteLimit(4096)
  result.completion.execution.initial.guests.initialization.envelope = InitializationByteLimit(4096)
  result.completion.execution.initial.guests.copyBytes = MemoryByteLimit(3024)
  result.completion.execution.execution.round.guests.preimageBytes = ByteLimit(4096)
  result.completion.execution.execution.round.guests.initialization.envelope = InitializationByteLimit(4096)
  result.completion.execution.execution.round.guests.copyBytes = MemoryByteLimit(3024)
