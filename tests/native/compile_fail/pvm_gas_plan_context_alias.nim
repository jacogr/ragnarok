# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copy a context-held pricing handle before borrowing that context mutably; direct input/storage aliasing is rejected.
# @@Verification={"build_name": "pvm-gas-plan-context-alias", "expected": "mutable argument aliases with immutable parameter", "group": "ownership_compile"}
import ../../../src/pvm/[program, machine, gas, gas_plan, step]
type Context = object ## The mutable callback context can replace its policy field.
  plan: GasPlan
proc respond(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## A legal context update cannot invalidate a separately retained policy value.
  context.plan = default(GasPlan)
  let info = machineInfo(stopped.machine).value
  HostResponse(action: HostAction.Halt, gas: info.gas, gasDeficit: GasDeficit(0),
    registers: info.registers, memory: memoryOf(stopped.machine).value)
let owner = decodeProgram([0'u8, 0, 1, 0, 1], CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
var context = Context(plan: newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(2),
  bytes: GasPlanByteLimit(128), cycles: GasCycleLimit(100))).value)
let source = captureMachine(owner, captureMemory([], PageLimit(0)).value,
  MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), gasDeficit: GasDeficit(0),
    registers: default(RegisterFile), blockCharged: false)).value
discard executeWithHost(source, context, respond, ExecutionStepLimit(1), HostCallLimit(1), context.plan)
