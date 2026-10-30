# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed accumulation capture must not expose a partial context or encoded input list.

import std/cmdline
import ../../src/codec/[c2_records, bounded]
import ../../src/pvm/host/fetch as host_fetch
let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
  FetchPresence.Absent, [], FetchTraceLimit(0)).value
var limits = FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(154),
  operand: OperandLimits(maxBytes: ByteLimit(153)))
let inputs = [transferSource(DeferredTransfer())]
case paramStr(1)
of "context":
  # Absence does not repair an invalid base context.
  discard withFetchAccumulation(default(FetchContext), FetchPresence.Absent, [], limits).value
of "count":
  # Descriptor policy is checked before walking or allocating input bytes.
  limits.items = ElementLimit(0)
  discard withFetchAccumulation(base, FetchPresence.Present, inputs, limits).value
of "operand":
  # Per-record policy remains independent of the whole encoded-list budget.
  limits.operand.maxBytes = ByteLimit(152)
  discard withFetchAccumulation(base, FetchPresence.Present, inputs, limits).value
else:
  # The list prefix is part of the aggregate budget, beyond the 153-byte transfer.
  limits.bytes = ByteLimit(153)
  discard withFetchAccumulation(base, FetchPresence.Present, inputs, limits).value
