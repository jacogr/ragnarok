# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original host-12 argument rows and real empty inner maps shared by page unit and misuse probes.

import ../../src/pvm/inner_machines as pvm_inner_machines
import ../../src/pvm/machine as pvm_machine
import ./pvm_inner_lifecycle

proc pageRegisters*(mode = 2'u64, first = 16'u64, count = 1'u64, id = 0'u64): RegisterFile =
  ## Full-width register arguments preserve malformed values without narrowing page geometry prematurely.
  result = innerRegisters()
  result[7] = RegisterValue(id)
  result[8] = RegisterValue(first)
  result[9] = RegisterValue(count)
  result[10] = RegisterValue(mode)
proc pageMachines*(limit = 4'u32): InnerMachines =
  ## Create a genuine empty-memory inner machine from a literal validated blob under a captured page policy.
  var cap = innerLimits()
  cap.pages = PageLimit(limit)
  let memory = innerMemory()
  let created = preparedInnerMachine(captureInnerMachines(cap), MachineGas(10000), innerRegisters(), memory).value
  created.machines
