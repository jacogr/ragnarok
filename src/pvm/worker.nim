# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit sequential execution workers retain one decoded source and one source/policy-bound prepared cache.
## CPU, memory, arguments, gas and callbacks are rebuilt per invocation; no process-global state is retained.

import ./[program, machine, initialize, step]
import ./gas/gas

type
  WorkerData = ref object ## Acyclic code-only storage has no back-reference to application inputs or published outputs.
    initialization: InitializationCode
    prepared: PreparedProgramCache
  ExecutionWorker* = object ## Copyable identity for one exclusive synchronous worker; never share it across threads.
    data: nil WorkerData

proc newExecutionWorker*(): ExecutionWorker =
  ## Allocate one empty bounded worker slot; retiring its last handle releases code and executable cache storage.
  ExecutionWorker(data: WorkerData(prepared: newPreparedProgramCache()))

func initialized*(worker: ExecutionWorker): bool =
  ## A default worker selects ordinary one-shot behavior; explicit creation enables retained code lifetimes.
  worker.data != nil

proc initializeMachine*(input, arguments: openArray[byte], entry: CodeAddress,
    gas: MachineGas, limits: InitializationLimits, worker: ExecutionWorker): InitializationResult =
  ## Recheck all envelope, allocation and entry rules while sharing only exact JAM code and identical parse policies.
  let data = worker.data
  if data == nil: return initializeMachine(input, arguments, entry, gas, limits)
  initializeMachine(input, arguments, entry, gas, limits, data.initialization)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, worker: ExecutionWorker): HostExecutionResult[Reason] =
  ## Retain prepared code only; exact source/backend/resource policy and busy refusal stay in the shared engine API.
  let data = worker.data
  if data == nil: return executeWithHost(source, context, handler, steps, calls, cycles, selected)
  executeWithHost(source, context, handler, steps, calls, cycles, selected, data.prepared)
