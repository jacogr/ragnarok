# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit finite host policy admits the known full authorization queue and code envelopes in fixed guest STF cases.
import ./[fuzz_backend_context, trace_check_context]
import ../../src/app/fuzz_backend
import ../../src/codec/bounded
import ../../src/pvm/[initialize, machine]
proc fuzzGuestReplayConfig*(): FuzzBackendConfig =
  ## Host resource ceilings cover the independently authored2560-byte queue; consensus validation is unchanged.
  result = fuzzBackendTestConfig()
  result.candidate = traceCheckTestPolicy().candidate
  result.initialAncestry = true
  result.forkStates = ElementLimit(2)
  result.candidate.completion.composition.validators.preimageBytes = ByteLimit(4096)
  result.candidate.completion.composition.activity.preimages.perBlob = ByteLimit(4096)
  result.candidate.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(4096)
  result.candidate.completion.composition.preimages.bytes = ByteLimit(4096)
  result.candidate.completion.execution.initial.guests.preimageBytes = ByteLimit(4096)
  result.candidate.completion.execution.initial.guests.initialization.envelope = InitializationByteLimit(4096)
  result.candidate.completion.execution.initial.guests.copyBytes = MemoryByteLimit(2560)
  result.candidate.completion.execution.execution.round.guests.preimageBytes = ByteLimit(4096)
  result.candidate.completion.execution.execution.round.guests.initialization.envelope = InitializationByteLimit(4096)
  result.candidate.completion.execution.execution.round.guests.copyBytes = MemoryByteLimit(2560)
