# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

type SieveInvocation* = object ## Opaque setup result excludes equal source capture from all hot timings.
  source: Machine
  cache: InstructionCache

proc bindSieve*(plan: PreparedProgram, memory: Memory, info: MachineInfo): SieveInvocation =
  ## Trusted benchmark fixtures are checked before timing; program binding stays private.
  let retained = plan.cache
  assert retained != nil
  let table: CacheData = retained
  let captured = captureMachine(table.owner, memory, info)
  assert captured.error == MachineError.None
  SieveInvocation(source: captured.value, cache: retained)

proc executeSieve*(invocation: SieveInvocation, stepLimit: ExecutionStepLimit,
    gasLimit: GasCycleLimit): StepResult =
  ## Preserve the original execution body with a read-only bound source/program pair.
  var remaining = uint64(stepLimit)
  var prices = initBlockChargeCache()
  var unusedCursor = default(ExecutionCursor) # Preserve the ordinary fresh-invocation validation path.
  executeBudget(invocation.source, remaining, gasLimit, prices, invocation.cache, unusedCursor, false)
