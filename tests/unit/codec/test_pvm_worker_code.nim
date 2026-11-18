# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_worker_code_arc_release"}

## Literal initialization and guest expectations verify exact-source worker reuse, replacement and invocation isolation.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, initialize, step, worker]
import ../../../src/pvm/gas/gas
import ../../support/arc_evidence

proc envelope(last = 0'u8): seq[byte] =
  ## Independent Y framing: one writable sentinel, two host/halt instructions and their literal instruction mask.
  @[0'u8, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 91, 8, 0, 0, 0, 0, 0, 4, 10, last, 50, 0, 5]

func limits(): InitializationLimits =
  ## All decode and memory allocations are explicitly finite and independent of gas/attempt budgets.
  InitializationLimits(envelope: InitializationByteLimit(128), program: ProgramByteLimit(64),
      jumps: JumpCountLimit(0), pages: PageLimit(2))

proc initialized(worker: ExecutionWorker, args: openArray[byte], gas = 100'u64): Machine =
  ## Extract only a completely admitted CPU; arguments and gas remain specific to this invocation.
  let created = initializeMachine(envelope(), args, CodeAddress(0), MachineGas(gas), limits(), worker)
  assert created.error == InitializationError.None
  created.value

type
  HostProbeError {.pure.} = enum
    Unexpected # The positive callback returns a response and never fabricates a host failure.
  HostProbe = object ## Callback-owned observations cannot enter the reusable prepared cache.
    cache: PreparedProgramCache
    other: Program
    calls: int
    observed: Memory

proc probeHost(context: var HostProbe, stopped: StepOutcome): HostResult[HostProbeError] {.raises: [].} =
  ## Reentry with another source must refuse before replacing the actively leased cache identity.
  inc context.calls
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 0
  let attempted = cachedPreparedProgram(context.cache, context.other,
      defaultPreparedLimits(GasCycleLimit(1000)), PvmBackend.Interpreted)
  assert attempted.error == PreparationError.Busy
  context.observed = stopped.machine.memoryOf.value
  let cpu = stopped.machine.machineInfo.value
  hostSuccess[HostProbeError](HostResponse(action: HostAction.Panic, gas: MachineGas(77),
      gasDeficit: GasDeficit(0), registers: cpu.registers, memory: context.observed))

proc retainedLifecycle() =
  ## One worker never retains an invocation's RAM or CPU after its synchronous callbacks return.
  let worker = newExecutionWorker()
  let first = initialized(worker, [1'u8], 100)
  let second = initialized(worker, [2'u8], 101)
  assert programOf(first).value == programOf(second).value
  assert uint64(second.machineInfo.value.gas) == 101
  assert first.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 1
  assert second.memoryOf.value.pageImage(PageIndex(0xfeff0000'u32 div 4096)).value.bytes[0] == 2
  var policy = limits()
  policy.jumps = JumpCountLimit(1)
  let changedPolicy = initializeMachine(envelope(), [], CodeAddress(0), MachineGas(100), policy, worker)
  assert changedPolicy.error == InitializationError.None
  assert programOf(changedPolicy.value).value != programOf(first).value
  let changedCode = initializeMachine(envelope(1), [], CodeAddress(0), MachineGas(100), policy, worker)
  assert changedCode.error == InitializationError.None
  assert programOf(changedCode.value).value != programOf(changedPolicy.value).value
  let invalidEntry = initializeMachine(envelope(1), [], CodeAddress(1), MachineGas(100), policy, worker)
  assert invalidEntry.error == InitializationError.InvalidProgram
  assert programOf(first).value != programOf(initialized(newExecutionWorker(), [1'u8])).value
  let cache = newPreparedProgramCache()
  let source = programOf(first).value
  let settings = defaultPreparedLimits(GasCycleLimit(1000))
  let admitted = cachedPreparedProgram(cache, source, settings, PvmBackend.Interpreted)
  assert admitted.error == PreparationError.None
  let completed = execute(first, ExecutionStepLimit(10), admitted.value)
  assert completed.error == StepError.None and completed.value.exit == StepExit.Host
  assert uint64(completed.value.machine.machineInfo.value.pc) == 0
  assert uint64(completed.value.hostCall) == 0
  let nodes = preparedInfo(admitted.value).value.streamNodes
  assert nodes > 0
  let reused = cachedPreparedProgram(cache, source, settings, PvmBackend.Interpreted)
  assert reused.error == PreparationError.None and preparedInfo(reused.value).value.streamNodes == nodes
  var smaller = settings
  smaller.resources.nodes = ExecutionNodeLimit(1)
  let replaced = cachedPreparedProgram(cache, source, smaller, PvmBackend.Interpreted)
  assert replaced.error == PreparationError.None and preparedInfo(
      replaced.value).value.streamNodes == 0
  let sourceChanged = cachedPreparedProgram(cache, programOf(changedCode.value).value, settings,
      PvmBackend.Interpreted)
  assert sourceChanged.error == PreparationError.None
  assert programOf(sourceChanged.value).value == programOf(changedCode.value).value
  var refusedPolicy = settings
  refusedPolicy.resources.codeBytes = ProgramByteLimit(0)
  let unavailable = cachedPreparedProgram(cache, source, refusedPolicy, PvmBackend.Interpreted)
  assert unavailable.error == PreparationError.LimitExceeded
  let afterFailure = cachedPreparedProgram(cache, programOf(changedCode.value).value, settings,
      PvmBackend.Interpreted)
  assert afterFailure.error == PreparationError.None
  assert programOf(afterFailure.value).value == programOf(changedCode.value).value
  var probe = HostProbe(cache: cache, other: programOf(changedCode.value).value, calls: 0)
  let hosted = executeWithHost(first, probe, probeHost, ExecutionStepLimit(10), HostCallLimit(1),
      GasCycleLimit(1000), PvmBackend.Interpreted, cache)
  assert hosted.error == HostExecutionError.None and probe.calls == 1
  assert hosted.value.exit == StepExit.Panic
  assert uint64(hosted.value.machine.machineInfo.value.pc) == 0
  assert uint64(hosted.value.machine.machineInfo.value.gas) == 77
  assert hosted.value.machine.memoryOf.value.pageImage(PageIndex(32)).value.bytes[0] == 91
  assert probe.observed.pageImage(PageIndex(32)).value.bytes[0] == 91
  let jitPolicy = cachedPreparedProgram(cache, source, settings, PvmBackend.Jit)
  assert jitPolicy.error == PreparationError.None
  assert preparedInfo(jitPolicy.value).value.backend == PvmBackend.Jit
  assert preparedInfo(jitPolicy.value).value.streamNodes == 0

proc budgetLifecycle() =
  ## Compete for one exact one-page idle charge through independent prepared owners.
  ## A complete RW page counts twice, once for the baseline and once for private bytes.
  let budget = newRetainedMemoryBudget(RetainedMemoryByteLimit(8192))
  let original = initialized(newExecutionWorker(), [])
  let source = programOf(original).value
  let policy = defaultPreparedLimits(GasCycleLimit(1000))
  let second = newPreparedProgramCache(memoryBudget = budget)
  let other = cachedPreparedProgram(second, source, policy, PvmBackend.Interpreted)
  assert other.error == PreparationError.None
  block:
    # One admitted owner fills the allowance. A distinct owner keeps ordinary execution.
    let first = newPreparedProgramCache(memoryBudget = budget)
    let kept = cachedPreparedProgram(first, source, policy, PvmBackend.Interpreted)
    assert kept.error == PreparationError.None
    let done = execute(original, ExecutionStepLimit(10), kept.value)
    assert done.error == StepError.None and done.value.exit == StepExit.Host
    assert retainedMemoryPayloadBytes(budget) == 8192
    let refused = execute(original, ExecutionStepLimit(10), other.value)
    assert refused.error == StepError.None and refused.value.exit == StepExit.Host
    assert refused.value.machine.machineInfo.value == done.value.machine.machineInfo.value
    assert refused.value.machine.memoryOf.value.pageImage(PageIndex(32)).value.bytes[0] == 91
    assert preparedInfo(other.value).value.retainedMemoryPayloadBytes == 0
    assert retainedMemoryPayloadBytes(budget) == 8192
    # Reuse consumes and replaces the charge once. Other owners never observe a double debit.
    let reused = execute(original, ExecutionStepLimit(10), kept.value)
    assert reused.error == StepError.None and reused.value.exit == StepExit.Host
    assert preparedInfo(kept.value).value.memoryReuses == 1
    assert retainedMemoryPayloadBytes(budget) == 8192
  assert retainedMemoryPayloadBytes(budget) == 0
  let allowed = execute(original, ExecutionStepLimit(10), other.value)
  assert allowed.error == StepError.None and allowed.value.exit == StepExit.Host
  assert retainedMemoryPayloadBytes(budget) == 8192
  # A cache replacement leaves bytes charged until the last independent prepared handle drops.
  let replacement = cachedPreparedProgram(second, source, policy, PvmBackend.Jit)
  assert replacement.error == PreparationError.None
  assert preparedInfo(other.value).value.retainedMemoryPayloadBytes == 8192
  assert retainedMemoryPayloadBytes(budget) == 8192

proc codeBudgetLifecycle() =
  ## Test source-only admission, warm stream refusal and shared release with real invocations.
  let sourceBudget = newRetainedMemoryBudget(RetainedMemoryByteLimit(8))
  let original = block:
    let first = newExecutionWorker(codeBudget = sourceBudget)
    let second = newExecutionWorker(codeBudget = sourceBudget)
    let retained = initialized(first, [])
    assert programOf(initialized(first, [])).value == programOf(retained).value
    let refused = initialized(second, [])
    assert programOf(refused).value != programOf(initialized(second, [])).value
    assert programOf(refused).value.programEncodingLength == 8
    assert retainedMemoryPayloadBytes(sourceBudget) == 8
    retained
  # An invocation snapshot can outlive the optional source cache and its charge.
  assert retainedMemoryPayloadBytes(sourceBudget) == 0
  let source = programOf(original).value
  let policy = defaultPreparedLimits(GasCycleLimit(1000))
  let reference = newPreparedProgram(source, policy)
  assert reference.error == PreparationError.None
  let cold = preparedInfo(reference.value).value.retainedCodePayloadBytes
  let expected = execute(original, ExecutionStepLimit(10), reference.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Host
  let warm = preparedInfo(reference.value).value.retainedCodePayloadBytes
  assert cold > 8 and warm > cold
  block:
    # One cold owner fits, but its warm stream must be discarded after a valid return.
    let budget = newRetainedMemoryBudget(RetainedMemoryByteLimit(cold))
    let cache = newPreparedProgramCache(codeBudget = budget)
    let admitted = cachedPreparedProgram(cache, source, policy, PvmBackend.Jit)
    assert admitted.error == PreparationError.None
    for attempt in 0..<2:
      # Dropping the optional stream preserves host ID, registers, gas and memory.
      let completed = execute(original, ExecutionStepLimit(10), admitted.value)
      assert completed.error == StepError.None and completed.value.exit == expected.value.exit
      assert completed.value.hostCall == expected.value.hostCall
      assert completed.value.machine.machineInfo.value == expected.value.machine.machineInfo.value
      assert completed.value.machine.memoryOf.value.pageImage(PageIndex(32)).value.bytes[0] == 91
      assert preparedInfo(admitted.value).value.streamNodes == 0
      assert retainedMemoryPayloadBytes(budget) == cold
  let budget = newRetainedMemoryBudget(RetainedMemoryByteLimit(warm))
  var held = default(PreparedProgram)
  block:
    # A prepared alias outlives the cache and keeps the actual source/stream charge.
    let cache = newPreparedProgramCache(codeBudget = budget)
    let admitted = cachedPreparedProgram(cache, source, policy, PvmBackend.Interpreted)
    assert admitted.error == PreparationError.None
    held = admitted.value
    assert execute(original, ExecutionStepLimit(10), held).error == StepError.None
    assert retainedMemoryPayloadBytes(budget) == warm
  assert preparedInfo(held).value.retainedCodePayloadBytes == warm
  let retry = newPreparedProgramCache(codeBudget = budget)
  block:
    # Admission pressure still produces a usable one-shot owner and no cache replacement.
    let refused = cachedPreparedProgram(retry, source, policy, PvmBackend.Interpreted)
    assert refused.error == PreparationError.None
    assert execute(original, ExecutionStepLimit(10), refused.value).error == StepError.None
    assert preparedCacheInfo(retry).error == PreparationError.InvalidProgram
    assert retainedMemoryPayloadBytes(budget) == warm
    # The hosted one-shot path excludes callback reentry without retaining the temporary owner.
    var probe = HostProbe(cache: retry, other: source, calls: 0)
    let hosted = executeWithHost(original, probe, probeHost, ExecutionStepLimit(10), HostCallLimit(1),
      GasCycleLimit(1000), PvmBackend.Interpreted, retry)
    assert hosted.error == HostExecutionError.None and probe.calls == 1
    assert hosted.value.exit == StepExit.Panic and preparedCacheInfo(retry).error ==
      PreparationError.InvalidProgram
  held = default(PreparedProgram)
  assert retainedMemoryPayloadBytes(budget) == 0
  let admitted = cachedPreparedProgram(retry, source, policy, PvmBackend.Interpreted)
  assert admitted.error == PreparationError.None
  assert execute(original, ExecutionStepLimit(10), admitted.value).error == StepError.None
  assert preparedCacheInfo(retry).value.prepared.retainedCodePayloadBytes == warm

retainedLifecycle()
budgetLifecycle()
codeBudgetLifecycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Both unbound and shared-budget ownership must return every allocation.
  retainedLifecycle()
  budgetLifecycle()
  codeBudgetLifecycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_worker_code", 1000, before, after)
echo "PVM worker code passed"
echo "ARC_RELEASE cycles=1000 unchanged"
