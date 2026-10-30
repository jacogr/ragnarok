# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Parameter capture and configuration refusals must never expose success payloads.

import std/cmdline
import ../../src/chain/parameters
import ../../src/pvm/host/fetch as host_fetch
import ../../src/pvm/machine

# Return a default snapshot through a runtime call for the encoder precondition probe.
proc missing(): Parameters = default(Parameters)

let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
  FetchPresence.Absent, [], FetchTraceLimit(0)).value
case paramStr(1)
of "encode":
  # The public encoder may not serialize an unvalidated default snapshot.
  discard encodeParameters(missing())
of "context":
  # Parameter attachment cannot repair an invalid invocation context.
  discard withFetchParameters(default(FetchContext), default(Parameters)).value
of "parameters":
  # A default chain snapshot is a local error, not a valid all-zero parameter tuple.
  discard withFetchParameters(base, default(Parameters)).value
else:
  # Selector 0 cannot expose a fabricated NONE or zero tuple before configuration is attached.
  let memory = captureMemory([], PageLimit(0)).value
  discard fetchContextResponse(base, MachineGas(1000), default(RegisterFile), memory,
    MemoryByteLimit(0)).value
