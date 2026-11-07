# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 gas host function and unknown-call fallback with unsigned saturating gas charges.
## Exposes gasHostResponse and unknownHostResponse for trusted host dispatchers. Neither owns context
## nor performs external effects; scalar replies copy CPU state and owned wrappers retain memory.

import ../[machine, step]

func charged(gas: MachineGas, cost: uint64, registers: RegisterFile): ScalarHostResponse =
  ## Subtract a fixed, bounded protocol cost without signed narrowing or unsigned underflow.
  ## Underfunding drains the complete unsigned balance to zero.
  let available = uint64(gas)
  if available < cost:
    # The failed comparison selects zero without unsigned subtraction.
    return ScalarHostResponse(action: HostAction.OutOfGas, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers)
  ScalarHostResponse(action: HostAction.Continue, gas: MachineGas(available - cost),
    gasDeficit: GasDeficit(0), registers: registers)

func gasHostResponse*(gas: MachineGas, registers: RegisterFile): ScalarHostResponse =
  ## Evaluate Omega_G (host identifier 0): cost 48, then return remaining gas in r7 only if affordable.
  ## The dispatcher supplies the active balance and identifier; scalar replies carry no memory authority.
  result = charged(gas, 48, registers)
  if result.action == HostAction.Continue:
    # General-host underfunding precedes table mutations, so r7 stays untouched on OutOfGas.
    result.registers[7] = RegisterValue(uint64(result.gas))

func unknownHostResponse(gas: MachineGas, registers: RegisterFile): ScalarHostResponse =
  ## Evaluate only the invocation dispatcher's unknown-call branch, not an unimplemented known call.
  ## Its WHAT return register is assigned even on underflow, unlike the general-function gas rule.
  result = charged(gas, 1000, registers)
  result.registers[7] = RegisterValue(high(uint64) - 1)

func ownedResponse(response: ScalarHostResponse, memory: Memory): HostResponse =
  ## Retain the legacy memory capability while sharing every protocol charge and register assignment.
  HostResponse(action: response.action, gas: response.gas, gasDeficit: response.gasDeficit,
    registers: response.registers, memory: memory)

func gasHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory): HostResponse =
  ## Existing snapshot callers retain their exact supplied owner and the same affordability ordering.
  ownedResponse(gasHostResponse(gas, registers), memory)

func unknownHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory): HostResponse =
  ## The legacy unknown branch shares WHAT and unsigned underfunding rules with scalar dispatch.
  ownedResponse(unknownHostResponse(gas, registers), memory)
