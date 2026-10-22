# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized guards reject response extraction after local owner/capacity failures and reject
## engine-reason extraction from completed zero-gas OOG.

import std/[assertions, cmdline]
import ../../src/pvm/[inner_machines, machine, step]
import ../support/[pvm_inner_lifecycle, pvm_inner_pages]

proc check(outcome: InnerMachineResult[InnerMachineTransition], expected: InnerMachineError) =
  ## Confirm the intended refusal while leaving the caller's later incorrect access dynamically checked.
  assert outcome.error == expected
let memory = innerMemory()
let source = pageMachines()
let success = innerPagesResponse(source, MachineGas(10000), pageRegisters(), memory)
check(success, InnerMachineError.None)
assert success.value.machines.innerMachine(InnerMachineId(0)).value.memory.pageImage(PageIndex(
    16)).value.access == PageAccess.ReadWrite
let missing = innerPagesResponse(default(InnerMachines), MachineGas(10000), pageRegisters(), memory)
check(missing, InnerMachineError.InvalidContext)
let invalid = innerPagesResponse(source, MachineGas(10000), pageRegisters(), default(Memory))
check(invalid, InnerMachineError.InvalidMemory)
let limited = innerPagesResponse(pageMachines(0), MachineGas(10000), pageRegisters(), memory)
check(limited, InnerMachineError.LimitExceeded)
let huge = innerPagesResponse(source, MachineGas(10000), pageRegisters(count = high(uint64)), memory)
check(huge, InnerMachineError.None)
assert huge.value.response.action == HostAction.OutOfGas and uint64(huge.value.response.gas) == 0, "wide unaffordable page cost is a genuine protocol OOG response"
case paramStr(1)
of "default-owner": discard missing.value # Invalid ownership carries no fabricated host response.
of "invalid-memory": discard invalid.value # Missing outer memory is a local API refusal.
of "capacity": discard limited.value # A page budget refusal exposes no partially mapped successor.
else: discard huge.executionError # Completed OOG cannot expose a local engine-failure reason.
