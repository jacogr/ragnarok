# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime probes ensure failed/default invocation-fetch results expose no completed context.

import std/cmdline
import ../../src/state/accumulation/[fetch as accumulation_fetch, inputs as accumulation_inputs]
import ../../src/pvm/host/fetch as host_fetch
let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
  FetchPresence.Absent, [], FetchTraceLimit(0)).value
# Dynamic selection keeps default refusal observable as a runtime contract check.
let outcome = if paramStr(1) == "default": default(InvocationFetchResult)
else: withInvocationFetch(base, default(PreparedAccumulationInputs),
  InvocationServiceIndex(0), default(FetchAccumulationLimits)) # No successful empty source.
case paramStr(1)
of "default":
  discard outcome.value # Unselected results contain no usable context.
of "context":
  discard withInvocationFetch(default(FetchContext), default(PreparedAccumulationInputs),
    InvocationServiceIndex(0), default(FetchAccumulationLimits)).value # Invalid bases cannot be repaired.
else:
  discard withInvocationFetch(base, default(PreparedAccumulationInputs),
    InvocationServiceIndex(0), default(FetchAccumulationLimits)).value # No fabricated empty service.
