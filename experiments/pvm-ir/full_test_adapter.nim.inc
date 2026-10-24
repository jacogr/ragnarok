# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only adapters replay unchanged public API witnesses through actual prepared entry points.
when defined(PreparedControls):
  proc testBinding(source: Machine, cycles: GasCycleLimit): PreparedResult[PreparedInvocation] =
    ## Each corpus invocation pays preparation outside the operation under test; default misuse stays typed.
    let owner = programOf(source)
    if owner.error != MachineError.None:
      return PreparedResult[PreparedInvocation](status: PreparedError.InvalidInput)
    var limits = defaultPreparedLimits()
    limits.cycles = cycles
    let code = prepareExecution(owner.value, limits)
    if code.error != PreparedError.None:
      return PreparedResult[PreparedInvocation](status: code.error)
    bindPrepared(code.value, source)
  proc testStep(source: Machine, cycles: GasCycleLimit, scope: int): StepResult =
    ## Replay capability/error precedence through the complete prepared single-step interface.
    let input = testBinding(source, cycles)
    if input.error != PreparedError.None: return StepResult(status: StepError.InvalidMachine)
    case scope
    of 0: stepRegisters(input.value)
    of 1: stepControl(input.value)
    of 2: stepMemory(input.value)
    else: stepOnce(input.value)
  proc testStepRegisters*(source: Machine, cycles: GasCycleLimit): StepResult =
    ## Register corpus adapter.
    testStep(source, cycles, 0)
  proc testStepControl*(source: Machine, cycles: GasCycleLimit): StepResult =
    ## Control corpus adapter.
    testStep(source, cycles, 1)
  proc testStepMemory*(source: Machine, cycles: GasCycleLimit): StepResult =
    ## Memory corpus adapter.
    testStep(source, cycles, 2)
  proc testStepOnce*(source: Machine, cycles: GasCycleLimit): StepResult =
    ## Full instruction corpus adapter.
    testStep(source, cycles, 3)
  proc testExecute*(source: Machine, steps: ExecutionStepLimit, cycles: GasCycleLimit): StepResult =
    ## Full execution corpus adapter; every attempt and gas limit is passed unchanged.
    let input = testBinding(source, cycles)
    if input.error != PreparedError.None: return StepResult(status: StepError.InvalidMachine)
    executePrepared(input.value, steps)
  proc testExecuteWithHost*[Context](source: Machine, context: var Context,
      handler: proc(context: var Context, stopped: StepOutcome): HostResponse {.nimcall, raises: [].},
      steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit): StepResult =
    ## Response-only host corpus adapter retains the prepared owner for the whole scheduler run.
    let input = testBinding(source, cycles)
    if input.error != PreparedError.None: return StepResult(status: StepError.InvalidMachine)
    executeWithHost(input.value, context, handler, steps, calls)
  proc testExecuteWithHost*[Context; Reason: enum](source: Machine, context: var Context,
      handler: proc(context: var Context, stopped: StepOutcome): HostResult[Reason] {.nimcall,
          raises: [].},
      steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit): HostExecutionResult[Reason] =
    ## Fallible host corpus adapter preserves callback failure selection and performed effects.
    let input = testBinding(source, cycles)
    if input.error != PreparedError.None:
      return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
    executeWithHost(input.value, context, handler, steps, calls)
