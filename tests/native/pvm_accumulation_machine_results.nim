# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime probes reject failed initialization and default accumulation-machine child extraction.

import std/cmdline
import ../../src/state/[accumulation_machine, accumulation_invocation]
import ../../src/pvm/[initialize, program, machine]
import ../support/pvm_accumulation_context
let limits = InitializationLimits(envelope: InitializationByteLimit(1000),
  program: ProgramByteLimit(100), jumps: JumpCountLimit(0), pages: PageLimit(0))
case paramStr(1)
of "machine":
  discard default(PreparedAccumulationMachine).accumulationMachine.value # Default owners expose no CPU.
of "heap":
  discard default(PreparedAccumulationMachine).machineHeapBounds.value # Default owners expose no envelope bounds.
of "bootstrap":
  discard default(PreparedAccumulationMachine).machineBootstrap.value # Default owners expose no provenance.
of "invocation":
  discard initializeAccumulationMachine(default(PreparedAccumulationInvocation), limits).value # Invalid source.
else:
  discard initializeAccumulationMachine(pvmBootstrap(pvmEnvelope()), limits).value # Page refusal has no owner.
