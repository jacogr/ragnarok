# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 gas host function and unknown-call fallback with exact terminal deficits.
## Exposes gasHostResponse and unknownHostResponse for trusted host dispatchers. Neither owns context
## nor performs external effects; responses retain immutable memory and copied registers.

import ./[machine, step]

# Subtract a fixed, bounded protocol cost without signed narrowing or unsigned underflow.
# Terminal negative gas is canonical zero credit plus a positive deficit, not a clamped balance.
func charged(gas: MachineGas, cost: uint64, registers: RegisterFile, memory: Memory): HostResponse =
  let available = uint64(gas)
  if available < cost:
    # Comparison proves subtraction safe; these fixed costs are far below the signed deficit bound.
    return HostResponse(action: HostAction.OutOfGas, gas: MachineGas(0),
      gasDeficit: GasDeficit(cost - available), registers: registers, memory: memory)
  HostResponse(action: HostAction.Continue, gas: MachineGas(available - cost),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)

func gasHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory): HostResponse =
  ## Evaluate Omega_G (host identifier 0): cost 48, then return remaining gas in r7 only if affordable.
  ## The dispatcher supplies an active nonnegative balance and selects the identifier; invalid memory
  ## is rejected when applying the response, not silently replaced here. Other state is unchanged.
  result = charged(gas, 48, registers, memory)
  if result.action == HostAction.Continue:
    # General-host underfunding precedes table mutations, so r7 stays untouched on OutOfGas.
    result.registers[7] = RegisterValue(uint64(result.gas))

func unknownHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory): HostResponse =
  ## Evaluate only the invocation dispatcher's unknown-call branch, not an unimplemented known call.
  ## Its WHAT return register is assigned even on underflow, unlike the general-function gas rule.
  result = charged(gas, 1000, registers, memory)
  result.registers[7] = RegisterValue(high(uint64) - 1)
