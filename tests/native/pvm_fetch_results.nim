# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed fetch-result extraction probes; each argument selects a distinct local refusal.

import std/cmdline
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/host_fetch as pvm_host_fetch
var regs = default(RegisterFile)
regs[10] = RegisterValue(2)
let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
  PageLimit(1)).value
case paramStr(1)
of "default":
  # Default results have no completed response.
  let emptyResult = default(FetchResult)
  discard emptyResult.value
of "selector":
  # A different selector cannot yield a response through the trace wrapper.
  regs[10] = RegisterValue(1)
  discard fetchTraceResponse(MachineGas(100), regs, memory, [], MemoryByteLimit(0)).value
of "memory":
  # Invalid owners are local errors even for empty copies.
  discard fetchTraceResponse(MachineGas(100), regs, default(Memory), [], MemoryByteLimit(0)).value
else:
  # Copy policy refusal carries neither the charged gas nor a partially written memory root.
  regs[9] = RegisterValue(1)
  discard fetchTraceResponse(MachineGas(100), regs, memory, [1'u8], MemoryByteLimit(0)).value
