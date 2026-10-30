# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed machine-derived fetch assembly cannot expose a partial immutable context.

import std/cmdline
import ../../src/state/accumulation/[fetch as accumulation_fetch, machine as accumulation_machine]
import ../../src/chain/parameters
import ../../src/pvm/[initialize, program, machine]
import ../../src/pvm/host/fetch as host_fetch
import ../../src/codec/[bounded, c2_records]
import ../support/pvm_accumulation_context
let prepared = initializeAccumulationMachine(pvmBootstrap(pvmEnvelope()),
  InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
    jumps: JumpCountLimit(0), pages: PageLimit(5))).value
case paramStr(1)
of "machine":
  discard machineFetchContext(default(PreparedAccumulationMachine), pvmParameters(),
    default(FetchAccumulationLimits)).value # No fabricated source selection.
of "parameters":
  discard machineFetchContext(prepared, default(Parameters), default(
      FetchAccumulationLimits)).value # No defaults.
else:
  discard machineFetchContext(prepared, pvmParameters(), default(
      FetchAccumulationLimits)).value # Empty list needs a byte.
