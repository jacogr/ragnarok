# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed machine-derived fetch assembly cannot expose a partial immutable context.

import std/cmdline
import ../../src/state/accumulation_fetch as state_accumulation_fetch
import ../../src/state/accumulation_machine as state_accumulation_machine
import ../../src/chain/parameters as chain_parameters
import ../../src/pvm/initialize as pvm_initialize
import ../../src/pvm/program as pvm_program
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/c2_records as codec_c2_records
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
