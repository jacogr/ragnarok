# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized guards reject failed invoke payloads and wrong-stage nested engine reasons after real positive controls.

import std/assertions
import std/cmdline
import ../../src/pvm/inner_machines as pvm_inner_machines
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/step as pvm_step
import ../support/pvm_inner_lifecycle
import ../support/pvm_inner_invoke

proc check(outcome: InnerMachineResult[InnerMachineTransition], reason: InnerMachineError) =
  ## Confirm genuine alternatives without exposing static caller knowledge to intentional guard misuse.
  assert outcome.error == reason
let memory = invokeMemory()
let source = invokeMachines()
let success = innerInvokeResponse(source, MachineGas(10000), invokeArgs(), memory)
check(success, InnerMachineError.None)
assert uint64(success.value.response.registers[7]) == 0
var cap = innerLimits()
cap.steps = ExecutionStepLimit(0)
let engine = innerInvokeResponse(invokeMachines(cap = cap), MachineGas(10000), invokeArgs(), memory)
check(engine, InnerMachineError.ExecutionFailure)
assert engine.executionError == StepError.StepLimitExceeded
let refused = innerInvokeResponse(default(InnerMachines), MachineGas(10000), invokeArgs(), memory)
check(refused, InnerMachineError.InvalidContext)
let invalid = innerInvokeResponse(source, MachineGas(10000), invokeArgs(), default(Memory))
check(invalid, InnerMachineError.InvalidMemory)
let underfunded = innerInvokeResponse(source, MachineGas(0), invokeArgs(), invokeMemory(fuel = high(uint64)))
check(underfunded, InnerMachineError.None)
assert underfunded.value.response.action == HostAction.OutOfGas and uint64(
    underfunded.value.response.gas) == 0, "wide unaffordable reservation produces completed zero-gas OOG"
let missing = default(InnerMachineResult[InnerMachineTransition])
check(missing, InnerMachineError.Uninitialized)
case paramStr(1)
of "engine": discard engine.value # Inner engine limits carry no completed frame or map.
of "owner": discard refused.value # Invalid map ownership carries no host response.
of "memory": discard invalid.value # Missing caller memory carries no charged protocol result.
of "oog-reason": discard underfunded.executionError # A valid OOG response has no local engine-failure reason.
of "success-reason": discard success.executionError # A successful inner halt has no local engine reason.
of "owner-reason": discard refused.executionError # Local context refusal cannot fabricate StepError.
else: discard missing.executionError # A default alternative has no nested engine reason.
