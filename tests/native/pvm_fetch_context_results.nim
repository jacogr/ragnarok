# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated optional-fetch capture and response failure probes.
## Each argument attempts success extraction from a default or refused alternative.

import std/cmdline
import ../../src/pvm/[machine, host_fetch]
let entropy = FetchEntropy(default(array[32, byte]))
case paramStr(1)
of "default":
  # Default capture results have no immutable context payload.
  let empty = default(FetchContextResult)
  discard empty.value
of "limit":
  # A trace exceeding the local snapshot budget exposes no partial owner.
  discard captureFetchContext(FetchPresence.Absent, entropy, FetchPresence.Present,
    [1'u8], FetchTraceLimit(0)).value
of "context":
  # Default context is distinct from a captured all-absent context.
  discard fetchContextResponse(default(FetchContext), MachineGas(1000), default(RegisterFile),
    captureMemory([], PageLimit(0)).value, MemoryByteLimit(0)).value
else:
  # A recognized but unsupported selector exposes no fabricated NONE response.
  let context = captureFetchContext(FetchPresence.Absent, entropy, FetchPresence.Absent, [],
    FetchTraceLimit(0)).value
  discard fetchContextResponse(context, MachineGas(1000), default(RegisterFile),
    captureMemory([], PageLimit(0)).value, MemoryByteLimit(0)).value
