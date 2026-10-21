# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized probes reject default/refused/missing lifecycle payload access after genuine positive controls.

import std/[assertions, cmdline]
import ../../src/pvm/[inner_machines, machine]
import ../support/pvm_inner_lifecycle

proc check[T](outcome: InnerMachineResult[T], reason: InnerMachineError) =
  ## Confirm the intended alternative without making the caller's misuse statically unreachable.
  assert outcome.error == reason
let empty = captureInnerMachines(innerLimits())
let success = preparedInnerMachine(empty, MachineGas(10000), innerRegisters(), innerMemory())
check(success, InnerMachineError.None)
assert success.value.machines.innerMachineCount.value == 1
let refused = preparedInnerMachine(default(InnerMachines), MachineGas(10000), innerRegisters(),
    innerMemory())
check(refused, InnerMachineError.InvalidContext)
let missing = empty.innerMachine(InnerMachineId(0))
check(missing, InnerMachineError.Missing)
var cap = innerLimits()
cap.items = InnerMachineLimit(0)
let limited = preparedInnerMachine(captureInnerMachines(cap), MachineGas(10000), innerRegisters(),
    innerMemory())
check(limited, InnerMachineError.LimitExceeded)
let defaultResult = default(InnerMachineResult[InnerMachineTransition])
check(defaultResult, InnerMachineError.Uninitialized)
case paramStr(1)
of "default": discard defaultResult.value # Default cannot expose success.
of "refused": discard refused.value # No invalid owner response may be extracted.
of "missing": discard missing.value # An absent slot has no invented empty program or PC.
of "limited": discard limited.value # Local exhaustion has no partially created map.
else: discard default(InnerMachines).innerMachineCount.value # A missing owner cannot claim zero cardinality.
