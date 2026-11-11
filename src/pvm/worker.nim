# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit sequential execution workers retain one decoded source and one source/policy-bound prepared cache.
## Logical CPU, arguments, gas and callbacks are rebuilt per invocation; bounded immutable memory
## baseline/private scratch may remain for restoration. No process-global state is retained.
## Construction binds an optional compiler runtime to this one prepared cache. The default
## selects checked execution even for requested Jit. Native image credits do not account for
## retained decoded facts or memory: convenience execution uses defaultPreparedLimits with
## a 64 MiB idle baseline/private-payload ceiling per prepared owner. A collection of workers
## needs its own aggregate retention policy; this wrapper has no environment-wide budget.

import ./[program, machine, initialize, step]
import ./gas/gas

type
  WorkerData = ref object ## Acyclic prepared storage has no live CPU/host/result/chain back-reference; bounded baseline/scratch may persist.
    initialization: InitializationCode
    prepared: PreparedProgramCache
  ExecutionWorker* = object ## Copyable identity for one exclusive synchronous worker; never share it across threads.
    data: nil WorkerData

proc newExecutionWorker*(nativeRuntime: NativeRuntime = default(NativeRuntime)): ExecutionWorker =
  ## Allocate one empty bounded worker slot; retiring its last handle releases code and executable cache storage.
  ExecutionWorker(data: WorkerData(prepared: newPreparedProgramCache(nativeRuntime)))

func initialized*(worker: ExecutionWorker): bool =
  ## A default worker selects ordinary one-shot behavior; explicit creation enables retained code lifetimes.
  worker.data != nil

proc workerInfo*(worker: ExecutionWorker): PreparationResult[PreparedCacheInfo] =
  ## Inspect actual retained preparation occupancy; an unprepared/busy worker cannot fabricate zero activity.
  let data = worker.data
  if data == nil: return preparedCacheInfo(default(PreparedProgramCache))
  preparedCacheInfo(data.prepared)

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

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason]
      {.nimcall, raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, worker: ExecutionWorker, scalarCalls: ScalarHostSelector,
    scalarHandler: FallibleScalarHostCallback[Context, Reason]): HostExecutionResult[Reason] =
  ## Scalar capability selection changes no retained key, callback lifetime or busy-owner contract.
  let data = worker.data
  if data == nil:
    return executeWithHost(source, context, handler, steps, calls, cycles, selected,
      scalarCalls, scalarHandler)
  executeWithHost(source, context, handler, steps, calls, cycles, selected, data.prepared,
    scalarCalls, scalarHandler)
