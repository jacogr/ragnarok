# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Real bounded compiler barrier, complete literal CPU/RAM histories, checked work receipts and final-drop cleanup.

import std/[assertions, syncio, envvars]
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/[handler_stream, native_pipeline, native_platform]

proc recordNativeQualification(kind: string, runtime: NativeRuntime, info: PreparedInfo,
    noRetryChecks = 0) =
  ## Emit only from supported, asserted native branches; standalone goldens remain unchanged.
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    # The CI caller supplies a fresh private directory; unsupported branches never write this proof.
    let isa = when defined(pvmX86Jit): "x86_64" else: "arm64"
    let observed = runtime.runtimeInfo
    let data = "{\"schema\":1,\"kind\":\"" & kind & "\",\"isa\":\"" & isa &
      "\",\"submitted\":" & $observed.submitted & ",\"completed\":" & $observed.completed &
      ",\"fragments\":" & $info.nativeFragments & ",\"calls\":" & $info.nativeCalls &
      ",\"operations\":" & $info.nativeOperations & ",\"no_retry_checks\":" & $noRetryChecks & "}\n"
    try:
      # Missing evidence cannot silently turn a native qualification into a checked fallback pass.
      writeFile(directory & "/pvm_shared_" & kind & "_" & isa & ".json", data)
    except:
      assert false, "shared native qualification evidence write failed"

proc diagnosticPhase(label: string) {.inline.} =
  ## Only the explicitly diagnostic image prints phases, outside existing public calls and barriers.
  when defined(pvmSharedAsyncDiagnostic):
    # Flush before the following witness so a first fatal assertion cannot hide its stage.
    stderr.writeLine("shared_async phase: " & label)
    stderr.flushFile()

proc launch(runtime: NativeRuntime): bool =
  ## Thread startup failure is an actual qualification failure, never a silent native skip.
  result = false
  try:
    result = runtime.start()
  except:
    assert false, "native compiler thread startup failed"

proc loopOwner(addend = 3'u8): Program =
  ## Wire header: no jump table, zero argument width, fourteen code bytes; trailing bytes are the start mask.
  ## Guest PC0 ADD_IMM_32 R7,R7,addend (default3, alternate5); PC3 ADD_IMM_32 R10,R10,1;
  ## PC6 BRANCH_LT_U R10,R11,PC0 (relative -6); PC12 JUMP_IND R0,0 (sentinel halt).
  assert addend in [3'u8, 5], "literal loop uses only the documented +3/+5 fixtures"
  let wire = @[0'u8, 0, 14, 131, 0x77, addend, 131, 0xaa, 1, 172, 0xba,
    0xfa, 0xff, 0xff, 0xff, 50, 0, 0x49, 0x10]
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "loopOwner.1: decoded.error == ProgramError.None"
  decoded.value

proc input(source: Program, iterations: uint64, gas = 1000000'u64): Machine =
  ## A complete immutable nonzero memory canary and fresh registers make stale invocation state observable.
  var page = PageImage(index: PageIndex(32), access: PageAccess.ReadWrite)
  for index in 0..<4096:
    page.bytes[index] = byte((index*17+29) and 255)
  let memory = captureMemory([page], PageLimit(1))
  assert memory.error == MachineError.None, "input.1: memory.error == MachineError.None"
  var registers = default(RegisterFile)
  for index in 0..<13: registers[index] = RegisterValue(uint64(index)*111)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[7] = RegisterValue(0)
  registers[10] = RegisterValue(0)
  registers[11] = RegisterValue(iterations)
  let captured = captureMachine(source, memory.value, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(gas), registers: registers))
  assert captured.error == MachineError.None, "input.2: captured.error == MachineError.None"
  captured.value

proc verifyState(result, source: Machine, iterations: uint64, addend = 3'u8) =
  ## Independent closed-form CPU/RAM oracle; +3 remains the original fixture, +5 detects image swaps.
  let info = machineInfo(result).value
  let initial = machineInfo(source).value
  assert uint64(initial.pc) == 0 and uint64(initial.gas) == 1000000 and
      uint64(initial.gasDeficit) == 0 and not initial.blockCharged,
      "verify.sourceCPU: original literal input remains unchanged"
  assert uint64(info.pc) == 0 and uint64(info.gasDeficit) == 0 and info.blockCharged,
      "verify.2: uint64(info.pc) == 0 and uint64(info.gasDeficit) == 0 and info.blockCharged" &
      "; pc=" & $uint64(info.pc) & "; deficit=" & $uint64(info.gasDeficit) & "; charged=" &
      $info.blockCharged
  # GP0.8 pipeline: overlapping ADD_IMM_32 pair then BRANCH_LT_U costs22 per loop block;
  # JUMP_IND costs22 too. Whole-block precharge is distinct from the3*N+1 original attempts.
  assert uint64(info.gas) == uint64(initial.gas)-22*(iterations+1),
      "verify.3: uint64(info.gas) == uint64(initial.gas)-22*(iterations+1)" & "; actual=" & $uint64(
      info.gas) & "; expected=" & $(uint64(initial.gas)-22*(iterations+1)) & "; iterations=" & $iterations
  for index in 0..<13:
    # The original input is an independent literal canary, not a potentially mutated comparison baseline.
    let original = if index == 0: 0xffff0000'u64
      elif index in [7, 10]: 0'u64
      elif index == 11: iterations else: uint64(index)*111
    assert uint64(initial.registers[index]) == original, "verify.sourceRegister: original literal canary"
    let expected = if index == 7: uint64(addend)*iterations elif index == 10: iterations
      else: uint64(initial.registers[index])
    assert uint64(info.registers[index]) == expected,
        "verify.4: uint64(info.registers[index]) == expected" & "; index=" & $index & "; actual=" &
        $uint64(info.registers[index]) & "; expected=" & $expected
  let after = pageImage(memoryOf(result).value, PageIndex(32)).value
  let before = pageImage(memoryOf(source).value, PageIndex(32)).value
  assert after.access == PageAccess.ReadWrite and before.access == PageAccess.ReadWrite, "verify.5: after.access == PageAccess.ReadWrite and before.access == PageAccess.ReadWrite"
  for index in 0..<4096:
    assert after.bytes[index] == byte((index*17+29) and 255),
        "verify.6: after.bytes[index] == byte((index*17+29) and 255)" & "; offset=" & $index &
        "; actual=" & $after.bytes[index]
    assert before.bytes[index] == after.bytes[index],
        "verify.7: before.bytes[index] == after.bytes[index]" & "; offset=" & $index & "; before=" &
        $before.bytes[index] & "; after=" & $after.bytes[index]
  assert uint64(machineInfo(source).value.registers[7]) == 0, "verify.8: uint64(machineInfo(source).value.registers[7]) == 0"
  assert programBytes(programOf(result).value).value == programBytes(programOf(source).value).value,
      "verify.source: immutable result preserves its complete wire owner"

proc verify(result: StepResult, source: Machine, iterations: uint64, addend = 3'u8) =
  ## Literal arithmetic/control and every RAM byte are independent of native/checked implementation details.
  assert result.error == StepError.None and result.value.exit == StepExit.Halt,
      "verify.1: result.error == StepError.None and result.value.exit == StepExit.Halt" &
      "; error=" & $uint8(result.error)
  verifyState(result.value.machine, source, iterations, addend)

proc prepared(source: Program, runtime: NativeRuntime): PreparedProgram =
  ## The exact immutable Program/policy owns its session; returning the handle never exposes the session graph.
  let made = newPreparedProgram(source, defaultPreparedLimits(GasCycleLimit(1000)),
    PvmBackend.Jit, runtime)
  assert made.error == PreparationError.None, "prepared.1: made.error == PreparationError.None"
  made.value

proc checkedReceipts() =
  ## Reservations are settled before observation: exact completion, zero/partial budget and unattempted OOG.
  let owner = loopOwner()
  let source = input(owner, 16)
  var admitted = prepareFlatPlan(owner, GasCycleLimit(1000), defaultFlatLimits(),
      allowNative = false)
  assert admitted.error == FlatError.None, "checkedReceipts.1: admitted.error == FlatError.None"
  let plan = takeValue(admitted)
  for budget in [0'u64, 1, 2, 47, 48, 49, 64]:
    var created = prepareFlatMemoryFrame(plan, memoryOf(source).value, machineInfo(source).value)
    assert created.error == FlatError.None, "checkedReceipts.2: created.error == FlatError.None"
    var frame = takeValue(created)
    runFlat(frame, budget)
    if budget < 49:
      assert frame.reason == StepError.StepLimitExceeded,
          "checkedReceipts.3: frame.reason == StepError.StepLimitExceeded" & "; budget=" & $budget &
          "; reason=" & $uint8(frame.reason) & "; exit=" & $uint8(frame.exit) & "; remaining=" &
          $frame.remaining & "; receipt=" & $settledNativeWork(frame, budget)
      assert settledNativeWork(frame, budget) == 0, "checkedReceipts.4: settledNativeWork(frame, budget) == 0"
    else:
      assert frame.reason == StepError.None and frame.exit == StepExit.Halt,
          "checkedReceipts.5: frame.reason == StepError.None and frame.exit == StepExit.Halt" &
          "; budget=" & $budget & "; reason=" & $uint8(frame.reason) & "; exit=" & $uint8(
          frame.exit) & "; remaining=" & $frame.remaining & "; receipt=" & $settledNativeWork(frame, budget)
      assert frame.remaining == budget-49 and settledNativeWork(frame, budget) == 48,
          "checkedReceipts.6: frame.remaining == budget-49 and settledNativeWork(frame, budget) == 48" &
          "; budget=" & $budget & "; reason=" & $uint8(frame.reason) & "; exit=" & $uint8(
          frame.exit) & "; remaining=" & $frame.remaining & "; receipt=" & $settledNativeWork(frame, budget)
  let poor = input(owner, 16, 0)
  var denied = prepareFlatMemoryFrame(plan, memoryOf(poor).value, machineInfo(poor).value)
  var frame = takeValue(denied)
  runFlat(frame, 64)
  assert frame.exit == StepExit.OutOfGas and settledNativeWork(frame, 64) == 0, "checkedReceipts.7: frame.exit == StepExit.OutOfGas and settledNativeWork(frame, 64) == 0"
  let plain = newPreparedProgram(owner, defaultPreparedLimits(), PvmBackend.Jit)
  assert plain.error == PreparationError.None, "checkedReceipts.8: plain.error == PreparationError.None"
  let done = execute(source, ExecutionStepLimit(49), plain.value)
  verify(done, source, 16)
  assert done.value.backend == PvmBackend.Interpreted, "checkedReceipts.9: done.value.backend == PvmBackend.Interpreted"

type HostContext = object
  ## Callback-owned runtime is a host-side handle; the compiler never sees it or this context.
  runtime: NativeRuntime
  calls: int

proc continueHost(context: var HostContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Both host segments preserve the existing paid CPU/RAM contract and refuse close of the active lease.
  assert stopped.exit == StepExit.Host, "continueHost.1: stopped.exit == StepExit.Host"
  inc context.calls
  assert uint64(stopped.hostCall) == uint64(6+context.calls), "continueHost.2: uint64(stopped.hostCall) == uint64(6+context.calls)"
  assert not context.runtime.close(), "continueHost.3: not context.runtime.close()"
  let cpu = stopped.machine.machineInfo.value
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: cpu.registers,
    memory: stopped.machine.memoryOf.value)

proc hostOwner(): Program =
  ## Wire header: no jump table, zero argument width, eighteen code bytes; trailing bytes are the start mask.
  ## PC0 ADD_IMM_32 R7,R7,3; PC3 ADD_IMM_32 R10,R10,1; PC6 ECALLI 7;
  ## PC8 ADD_IMM_32 R7,R7,3; PC11 ADD_IMM_32 R10,R10,1; PC14 ECALLI 8;
  ## PC16 JUMP_IND R0,0 (sentinel halt). Exactly seven original attempts across three host segments.
  let raw = @[0'u8, 0, 18, 131, 0x77, 3, 131, 0xaa, 1, 10, 7,
    131, 0x77, 3, 131, 0xaa, 1, 10, 8, 50, 0, 0x49, 0x49, 1]
  let decoded = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "hostOwner.1: decoded.error == ProgramError.None"
  decoded.value

proc closedHandleMoves() =
  ## Handle moves/copies retain one stable anchor; its initialized mutex storage never physically moves.
  var original = newNativeRuntime()
  let alias = original
  assert alias.close(), "closedHandleMoves.1: alias.close()"
  let transferred = move(original)
  assert not launch(original), "closedHandleMoves.2: not launch(original)" # Moved-from default has no runtime and cannot create a thread.
  assert transferred.close() and alias.close(), "closedHandleMoves.3: transferred.close() and alias.close()"
  assert default(NativeRuntime).close(), "closedHandleMoves.4: default(NativeRuntime).close()"

when defined(pvmSharedAsyncWitness):
  proc hostReceipts() =
    ## Literal disjoint settled work2+2+0 proves rolling host budgets cannot double-count prior segments.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported(): return
    assert launch(runtime), "hostReceipts.1: launch(runtime)"
    pauseNativeCompiler(runtime, true)
    let owner = hostOwner()
    let source = input(owner, 1)
    let session = newNativeSession(runtime)
    beginNativeInvocation(session, 64)
    var admitted = prepareFlatPlan(owner, GasCycleLimit(1000), defaultFlatLimits(),
        allowNative = false)
    let plan = takeValue(admitted)
    var created = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
    var frame = takeValue(created)
    var remaining = 64'u64
    for segment in 0..<3:
      let supplied = remaining
      runFlat(frame, supplied)
      remaining = frame.remaining
      let receipt = settledNativeWork(frame, supplied)
      assert receipt == (if segment < 2: 2'u64 else: 0'u64), "hostReceipts.2: receipt == (if segment < 2: 2'u64 else: 0'u64)"
      recordNativeWork(session, receipt)
      if segment < 2:
        assert frame.exit == StepExit.Host, "hostReceipts.3: frame.exit == StepExit.Host"
        let memory = observeFlatHostMemory(frame)
        let cpu = frame.info
        assert resumeFlatHostMemory(frame, memory, cpu.gas, cpu.registers) == StepError.None, "hostReceipts.4: resumeFlatHostMemory(frame, memory, cpu.gas, cpu.registers) == StepError.None"
      else:
        assert frame.exit == StepExit.Halt, "hostReceipts.5: frame.exit == StepExit.Halt"
    assert remaining == 57 and observedNativeWork(session) == 4, "hostReceipts.6: remaining == 57 and observedNativeWork(session) == 4"
    finishNativeInvocation(session, observedNativeWork(session))
    let code = prepared(owner, runtime)
    var host = HostContext(runtime: runtime)
    let answer = executeWithHost(source, host, continueHost, ExecutionStepLimit(64), HostCallLimit(
        2), code)
    assert answer.error == StepError.None and answer.value.exit == StepExit.Halt, "hostReceipts.7: answer.error == StepError.None and answer.value.exit == StepExit.Halt"
    assert host.calls == 2, "hostReceipts.8: host.calls == 2"
    let cpu = answer.value.machine.machineInfo.value
    assert uint64(cpu.registers[7]) == 6 and uint64(cpu.registers[10]) == 2, "hostReceipts.9: uint64(cpu.registers[7]) == 6 and uint64(cpu.registers[10]) == 2"
    assert runtime.runtimeInfo.submitted == 0, "hostReceipts.10: runtime.runtimeInfo.submitted == 0"
    assert runtime.close(), "hostReceipts.11: runtime.close()"

  proc staleStreamEpoch() =
    ## Same live source registration must reject an old queued image after a destructive stream epoch reset.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported(): return
    assert launch(runtime), "staleStreamEpoch.1: launch(runtime)"
    pauseNativeCompiler(runtime, true)
    let source = input(loopOwner(), 2048)
    let owner = source.programOf.value
    let session = newNativeSession(runtime)
    beginNativeInvocation(session, 6145)
    var admitted = prepareFlatPlan(owner, GasCycleLimit(1000), defaultFlatLimits(),
        allowNative = false)
    let plan = takeValue(admitted)
    var created = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
    var frame = takeValue(created)
    frame.nativeSession = session
    runFlat(frame, 6145)
    let old = nativeEpoch(session)
    assert nativeSpanInfo(session).len == 2, "staleStreamEpoch.2: nativeSpanInfo(session).len == 2"
    finishNativeInvocation(session, settledNativeWork(frame, 6145))
    assert nativeState(session) == NativeState.Pending, "staleStreamEpoch.3: nativeState(session) == NativeState.Pending"
    invalidateNativeStream(session)
    assert nativeEpoch(session) == old+1 and nativeState(session) == NativeState.Deferred, "staleStreamEpoch.4: nativeEpoch(session) == old+1 and nativeState(session) == NativeState.Deferred"
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    assert runtime.runtimeInfo.phase == NativePhase.Idle, "staleStreamEpoch.5: runtime.runtimeInfo.phase == NativePhase.Idle"
    assert nativeState(session) == NativeState.Deferred and nativeSpanInfo(session).len == 0, "staleStreamEpoch.6: nativeState(session) == NativeState.Deferred and nativeSpanInfo(session).len == 0"
    assert runtime.runtimeInfo.completed == 0, "staleStreamEpoch.7: runtime.runtimeInfo.completed == 0"
    assert runtime.close(), "staleStreamEpoch.8: runtime.close()"

when defined(pvmSharedAsyncWitness):
  proc asyncLifecycle() =
    ## No per-call readiness wait: blocked compiler permits first AND second checked outputs; real ready image follows.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported():
      assert not launch(runtime), "asyncLifecycle.1: not launch(runtime)"
      assert runtime.close(), "asyncLifecycle.2: runtime.close()"
      return
    assert launch(runtime), "asyncLifecycle.3: launch(runtime)"
    pauseNativeCompiler(runtime, true)
    let owner = loopOwner()
    let source = input(owner, 2048)
    let code = prepared(owner, runtime)
    let short = input(owner, 16)
    diagnosticPhase("asyncLifecycle: thirteen cold tiny calls")
    for call in 0..<13:
      # Thirteen completed short calls cannot add up to the one-call admission floor.
      let tiny = execute(short, ExecutionStepLimit(49), code)
      verify(tiny, short, 16)
      assert tiny.value.backend == PvmBackend.Interpreted, "asyncLifecycle.4: tiny.value.backend == PvmBackend.Interpreted"
      assert runtime.runtimeInfo.submitted == 0, "asyncLifecycle.5: runtime.runtimeInfo.submitted == 0"
      assert preparedNativeState(code).value == NativeState.Deferred, "asyncLifecycle.6: preparedNativeState(code).value == NativeState.Deferred"
    diagnosticPhase("asyncLifecycle: two blocked long calls")
    for call in 0..<2:
      let done = execute(source, ExecutionStepLimit(6145), code)
      verify(done, source, 2048)
      assert done.value.backend == PvmBackend.Interpreted, "asyncLifecycle.7: done.value.backend == PvmBackend.Interpreted"
      assert preparedNativeState(code).value == NativeState.Pending, "asyncLifecycle.8: preparedNativeState(code).value == NativeState.Pending"
      assert preparedInfo(code).value.nativeFragments == 0, "asyncLifecycle.9: preparedInfo(code).value.nativeFragments == 0"
      assert runtime.runtimeInfo.phase == NativePhase.Queued, "asyncLifecycle.10: runtime.runtimeInfo.phase == NativePhase.Queued"
      assert runtime.runtimeInfo.submitted == 1, "asyncLifecycle.11: runtime.runtimeInfo.submitted == 1"
    pauseNativeCompiler(runtime, false)
    diagnosticPhase("asyncLifecycle: compiler barrier")
    waitNativeCompiler(runtime) # Qualification synchronization OUTSIDE every invocation.
    diagnosticPhase("asyncLifecycle: first ready call")
    let done = execute(source, ExecutionStepLimit(6145), code)
    verify(done, source, 2048)
    assert done.value.backend == PvmBackend.Jit, "asyncLifecycle.12: done.value.backend == PvmBackend.Jit" &
        "; backend=" & $uint8(done.value.backend)
    assert preparedInfo(code).value.nativeFragments == 1, "asyncLifecycle.13: preparedInfo(code).value.nativeFragments == 1"
    assert preparedInfo(code).value.nativeOperations == 4096,
        "asyncLifecycle.14: preparedInfo(code).value.nativeOperations == 4096" & "; actual=" &
        $preparedInfo(code).value.nativeOperations
    assert not preparedInfo(code).value.nativeCompilationMeasured, "asyncLifecycle.15: not preparedInfo(code).value.nativeCompilationMeasured"
    diagnosticPhase("asyncLifecycle: sixteen ready tiny-budget calls")
    for call in 0..<16:
      let tiny = execute(short, ExecutionStepLimit(49), code)
      verify(tiny, short, 16)
      assert tiny.value.backend == PvmBackend.Interpreted, "asyncLifecycle.16: tiny.value.backend == PvmBackend.Interpreted"
    assert runtime.runtimeInfo.submitted == 1, "asyncLifecycle.17: runtime.runtimeInfo.submitted == 1"
    # A short input does not permanently blacklist the same Program: a later long input is reconsidered.
    diagnosticPhase("asyncLifecycle: ready long/tiny/long alternation")
    let firstLong = execute(source, ExecutionStepLimit(6145), code)
    verify(firstLong, source, 2048)
    assert firstLong.value.backend == PvmBackend.Jit,
        "asyncLifecycle.18: firstLong.value.backend == PvmBackend.Jit" & "; backend=" & $uint8(
        firstLong.value.backend)
    # Alternating source inputs retain the maximum proven single-call work; tiny budgets still refuse entry.
    let interleavedTiny = execute(short, ExecutionStepLimit(49), code)
    verify(interleavedTiny, short, 16)
    assert interleavedTiny.value.backend == PvmBackend.Interpreted, "asyncLifecycle.19: interleavedTiny.value.backend == PvmBackend.Interpreted"
    let nextLong = execute(source, ExecutionStepLimit(6145), code)
    verify(nextLong, source, 2048)
    assert nextLong.value.backend == PvmBackend.Jit,
        "asyncLifecycle.20: nextLong.value.backend == PvmBackend.Jit" & "; backend=" & $uint8(
        nextLong.value.backend)
    assert runtime.close(), "asyncLifecycle.21: runtime.close()" # Surviving code/session anchor remains valid, but can no longer enter native code.
    diagnosticPhase("asyncLifecycle: closed runtime call")
    let closed = execute(source, ExecutionStepLimit(6145), code)
    verify(closed, source, 2048)
    assert closed.value.backend == PvmBackend.Interpreted, "asyncLifecycle.22: closed.value.backend == PvmBackend.Interpreted"
    assert runtime.close(), "asyncLifecycle.23: runtime.close()"
    let observed = preparedInfo(code).value
    assert observed.nativeFragments > 0 and observed.nativeCalls > 0 and observed.nativeOperations > 0,
      "supported common qualification requires real publication and entry"
    recordNativeQualification("positive", runtime, observed)


  proc cancelledFinalDrop() =
    ## Retained output keeps only immutable guest state; it cannot pin a cancelled prepared/native owner.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported(): return
    assert launch(runtime), "cancelledFinalDrop.1: launch(runtime)"
    pauseNativeCompiler(runtime, true)
    let owner = loopOwner()
    let source = input(owner, 2048)
    var history = default(StepResult)
    block:
      let code = prepared(owner, runtime)
      history = execute(source, ExecutionStepLimit(6145), code)
      verify(history, source, 2048)
      assert runtime.runtimeInfo.registered == 1, "cancelledFinalDrop.2: runtime.runtimeInfo.registered == 1"
    assert runtime.runtimeInfo.registered == 1, "cancelledFinalDrop.3: runtime.runtimeInfo.registered == 1" # Queued orphan still consumes credit until real retirement.
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    assert runtime.runtimeInfo.phase == NativePhase.Idle, "cancelledFinalDrop.4: runtime.runtimeInfo.phase == NativePhase.Idle"
    assert runtime.runtimeInfo.registered == 0, "cancelledFinalDrop.5: runtime.runtimeInfo.registered == 0"
    verify(history, source, 2048)
    # The same runtime can admit a new exact owner after the cancelled slot is physically retired.
    block:
      let other = prepared(loopOwner(), runtime)
      let done = execute(source, ExecutionStepLimit(0), other)
      assert done.error == StepError.InvalidPreparedProgram,
          "cancelledFinalDrop.6: done.error == StepError.InvalidPreparedProgram" # Independent Program identity is not a cache hit.
    assert runtime.close(), "cancelledFinalDrop.7: runtime.close()"

when defined(pvmSharedAsyncWitness):
  proc readyReservations() =
    ## Real ready code must respect an original partial-attempt barrier and an unpaid OOG header.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported(): return
    assert launch(runtime), "readyReservations.1: launch(runtime)"
    let owner = loopOwner()
    let source = input(owner, 2048)
    let session = newNativeSession(runtime)
    var admitted = prepareFlatPlan(owner, GasCycleLimit(1000), defaultFlatLimits(),
        allowNative = false)
    let plan = takeValue(admitted)
    var created = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
    var frame = takeValue(created)
    frame.nativeSession = session
    beginNativeInvocation(session, 6145)
    runFlat(frame, 6145)
    finishNativeInvocation(session, settledNativeWork(frame, 6145))
    var stream = takeFlatStream(frame)
    waitNativeCompiler(runtime) # Explicit qualification barrier outside all public calls.
    for poor in [false, true]:
      # The partial call completes 1365 whole triples, then only R7+=3 of its final triple.
      # Zero-gas input attempts its first charge and must execute no native instruction.
      let selected = if poor: input(owner, 2048, 0) else: source
      var made = prepareFlatMemoryFrame(plan, selected.memoryOf.value, selected.machineInfo.value)
      var current = takeValue(made)
      current.nativeSession = session
      let budget = if poor: 6145'u64 else: 4096'u64
      let before = nativeStatistics(session)[2]
      beginNativeInvocation(session, budget)
      restoreFlatStream(current, stream)
      runFlat(current, budget)
      assert settledNativeWork(current, budget) == 0, "readyReservations.2: settledNativeWork(current, budget) == 0"
      if poor:
        assert current.reason == StepError.None and current.exit == StepExit.OutOfGas, "readyReservations.3: current.reason == StepError.None and current.exit == StepExit.OutOfGas"
        assert uint64(current.info.gas) == 0 and uint64(current.info.gasDeficit) == 0,
            "readyReservations.4: uint64(current.info.gas) == 0 and uint64(current.info.gasDeficit) == 0" &
            "; gas=" & $uint64(current.info.gas) & "; deficit=" & $uint64(current.info.gasDeficit)
        assert uint64(current.info.pc) == 0 and not current.info.blockCharged,
            "readyReservations.5: uint64(current.info.pc) == 0 and not current.info.blockCharged" &
            "; pc=" & $uint64(current.info.pc) & "; charged=" & $current.info.blockCharged
        assert current.remaining == budget, "readyReservations.6: current.remaining == budget"
        assert nativeStatistics(session)[2] == before, "readyReservations.7: nativeStatistics(session)[2] == before"
      else:
        assert current.reason == StepError.StepLimitExceeded and current.remaining == 0, "readyReservations.8: current.reason == StepError.StepLimitExceeded and current.remaining == 0"
        assert uint64(current.info.pc) == 3 and current.info.blockCharged,
            "readyReservations.9: uint64(current.info.pc) == 3 and current.info.blockCharged" &
            "; pc=" & $uint64(current.info.pc) & "; charged=" & $current.info.blockCharged
        # The final partial block is prepaid too:1366*22=30052 gas for4096 attempted source steps.
        assert uint64(current.info.gas) == 969948 and uint64(current.info.gasDeficit) == 0,
            "readyReservations.10: uint64(current.info.gas) == 969948 and uint64(current.info.gasDeficit) == 0" &
            "; gas=" & $uint64(current.info.gas) & "; deficit=" & $uint64(current.info.gasDeficit)
        assert nativeStatistics(session)[2]-before == 2730,
            "readyReservations.11: nativeStatistics(session)[2]-before == 2730" &
            "; actual delta=" & $(nativeStatistics(session)[2]-before) # Two ops in each complete triple only.
      for index in 0..<13:
        let expected = if not poor and index == 7: 4098'u64
          elif not poor and index == 10: 1365'u64
          else: uint64(selected.machineInfo.value.registers[index])
        assert uint64(current.info.registers[index]) == expected,
            "readyReservations.12: uint64(current.info.registers[index]) == expected" & "; index=" &
            $index & "; actual=" & $uint64(current.info.registers[index]) & "; expected=" & $expected
      let page = flatMemorySnapshot(current).pageImage(PageIndex(32)).value
      for offset in 0..<4096:
        assert page.bytes[offset] == byte((offset*17+29) and 255), "readyReservations.13: page.bytes[offset] == byte((offset*17+29) and 255)"
      finishNativeInvocation(session, 0) # Neither attempted partial work nor OOG buys a new admission.
      stream = takeFlatStream(current)
    assert runtime.close(), "readyReservations.14: runtime.close()"

  proc doneFinalDrop() =
    ## An uncollected successful image also occupies credit and must be reclaimed by final owner retirement.
    let runtime = newNativeRuntime()
    if not nativePlatformSupported(): return
    assert launch(runtime), "doneFinalDrop.1: launch(runtime)"
    let owner = loopOwner()
    let source = input(owner, 2048)
    var history = default(StepResult)
    block:
      let code = prepared(owner, runtime)
      history = execute(source, ExecutionStepLimit(6145), code)
      verify(history, source, 2048)
      waitNativeCompiler(runtime)
      assert runtime.runtimeInfo.phase == NativePhase.Done, "doneFinalDrop.2: runtime.runtimeInfo.phase == NativePhase.Done"
      assert runtime.runtimeInfo.completed == 1, "doneFinalDrop.3: runtime.runtimeInfo.completed == 1"
    waitNativeCompiler(runtime)
    assert runtime.runtimeInfo.phase == NativePhase.Idle and runtime.runtimeInfo.registered == 0, "doneFinalDrop.4: runtime.runtimeInfo.phase == NativePhase.Idle and runtime.runtimeInfo.registered == 0"
    verify(history, source, 2048)
    assert runtime.close(), "doneFinalDrop.5: runtime.close()"


when defined(pvmSharedAsyncWitness):
  proc runSharedAsyncRefusal*() =
    ## A real eligible worker job refuses allocation once; exact collection is permanently checked for this owner.
    when defined(pvmX86Jit):
      assert defined(pvmX86JitRefuse), "refusal requires the selected x86 allocation control"
    else:
      assert defined(pvmArm64Jit) and defined(pvmArm64JitRefuse),
          "refusal requires the selected ARM allocation control"
    let runtime = newNativeRuntime()
    let owner = loopOwner()
    let source = input(owner, 2048)
    var history: seq[StepResult] = @[]
    var refusedInfo = default(PreparedInfo)
    var noRetryChecks = 0
    if nativePlatformSupported():
      # Capability and startup must succeed: this branch proves worker allocation refusal, not unsupported fallback.
      assert launch(runtime), "refusal: supported runtime starts"
      pauseNativeCompiler(runtime, true)
      block:
        # This exact prepared owner holds the registration until all five literal outputs are retained.
        let code = prepared(owner, runtime)
        let first = execute(source, ExecutionStepLimit(6145), code)
        verify(first, source, 2048)
        history.add(first)
        assert first.value.backend == PvmBackend.Interpreted, "refusal: queued call stays checked"
        assert preparedNativeState(code).value == NativeState.Pending,
            "refusal: exact owner has pending ticket"
        let queued = runtime.runtimeInfo
        assert queued.phase == NativePhase.Queued and queued.submitted == 1 and
            queued.completed == 0,
            "refusal: one real queued job while compiler paused"
        assert queued.registered == 1 and queued.active == 0,
            "refusal: one credit, no active invocation"
        pauseNativeCompiler(runtime, false)
        waitNativeCompiler(runtime) # Deterministic barrier OUTSIDE every public call; no timed readiness loop.
        let completed = runtime.runtimeInfo
        assert completed.phase == NativePhase.Done and completed.submitted == 1 and
            completed.completed == 1,
            "refusal: worker completed one real job"
        assert completed.completions == 1, "refusal: nil image still occupies its own Complete row"
        assert preparedNativeState(code).value == NativeState.Pending,
            "refusal: worker never mutates host session before exact collection"
        for call in 0..<4:
          # First call collects the empty image; three more eligible calls must never requeue this owner.
          let done = execute(source, ExecutionStepLimit(6145), code)
          verify(done, source, 2048)
          history.add(done)
          assert done.value.backend == PvmBackend.Interpreted, "refusal: every result stays checked"
          assert preparedNativeState(code).value == NativeState.Unavailable,
              "refusal: empty completion permanently unavailable for this source epoch"
          let info = preparedInfo(code).value
          refusedInfo = info
          if call > 0:
            # The first collection is distinct from the three later eligible no-retry calls.
            inc noRetryChecks
          assert info.nativeFragments == 0 and info.nativeCalls == 0 and
              info.nativeOperations == 0 and info.nativeCodeBytes == 0,
              "refusal: no publication, native entry or executable occupancy"
          assert not info.nativeCompilationMeasured and info.nativeCompilationNs == 0,
              "refusal: unavailable duration is not a measured zero"
          let idle = runtime.runtimeInfo
          assert idle.phase == NativePhase.Idle and idle.submitted == 1 and idle.completed == 1,
              "refusal: exact empty collection frees mailbox without retry"
          assert idle.completions == 0, "refusal: empty collection retires the parked completion"
          assert idle.registered == 1 and idle.active == 0,
              "refusal: live owner retains only its credit"
      assert runtime.runtimeInfo.registered == 0, "refusal: final owner drop returns credit"
      assert history.len == 5, "refusal: five full literal outputs retained"
    else:
      # Nonmatching hosts still exercise truthful checked fallback; this is not an allocation-refusal receipt.
      assert not launch(runtime), "refusal: unsupported platform does not start a worker"
      block:
        let code = prepared(owner, runtime)
        let done = execute(source, ExecutionStepLimit(6145), code)
        verify(done, source, 2048)
        history.add(done)
        assert done.value.backend == PvmBackend.Interpreted,
            "refusal: unsupported result stays checked"
      assert runtime.runtimeInfo.submitted == 0 and runtime.runtimeInfo.registered == 0,
          "refusal: unsupported fallback has no worker job or retained credit"
    assert runtime.close(), "refusal: close joins the actual compiler before releasing its anchor"
    let closed = runtime.runtimeInfo
    assert closed.phase == NativePhase.Idle and closed.registered == 0 and closed.active == 0,
        "refusal: closed runtime has no owner, job or invocation"
    for done in history:
      # Retained immutable CPU/RAM results survive later calls, final prepared drop and compiler join.
      verify(done, source, 2048)
      assert programBytes(programOf(done.value.machine).value).value == programBytes(owner).value,
          "refusal: retained result preserves its immutable source"
    let original = machineInfo(source).value
    assert uint64(original.pc) == 0 and uint64(original.gas) == 1000000 and
        uint64(original.gasDeficit) == 0 and not original.blockCharged,
        "refusal: original CPU and gas remain literal after all calls and teardown"
    for index in 0..<13:
      # Check the original register file independently, rather than trusting a potentially mutated snapshot.
      let expected =
        if index == 0: 0xffff0000'u64
        elif index in [7, 10]: 0'u64
        elif index == 11: 2048'u64
        else: uint64(index)*111
      assert uint64(original.registers[index]) == expected,
          "refusal: immutable original register file"
    assert programBytes(owner).value == @[0'u8, 0, 14, 131, 0x77, 3, 131, 0xaa, 1, 172, 0xba,
        0xfa, 0xff, 0xff, 0xff, 50, 0, 0x49, 0x10], "refusal: original wire bytes remain literal"
    if nativePlatformSupported():
      # All literal histories, Unavailable/no-retry, returned-credit and close checks already passed.
      assert noRetryChecks == 3
      recordNativeQualification("refused", runtime, refusedInfo, noRetryChecks)
    echo "PVM shared async refusal controls passed"

when defined(pvmSharedAsyncWitness):
  proc retainedCompletionFairness() =
    ## Retained unused A parks +3 code while a real +5 B queues, collects and executes independently.
    if not nativePlatformSupported(): return
    let runtime = newNativeRuntime()
    assert launch(runtime), "retainedCompletionFairness.1"
    let sourceA = input(loopOwner(), 2048)
    let sourceB = input(loopOwner(5), 2048)
    var codeA = prepared(sourceA.programOf.value, runtime)
    var codeB = prepared(sourceB.programOf.value, runtime)
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    let firstA = execute(sourceA, ExecutionStepLimit(6145), codeA)
    verify(firstA, sourceA, 2048)
    assert firstA.value.backend == PvmBackend.Interpreted, "retainedCompletionFairness.2"
    let keyA = waitNativeCompilerGate(runtime)
    assert keyA.point == NativeCompilerPoint.AfterPublish and keyA.hasImage, "retainedCompletionFairness.3"
    assert runtime.runtimeInfo.completions == 1 and runtime.runtimeInfo.phase == NativePhase.Done, "retainedCompletionFairness.4"
    let firstB = execute(sourceB, ExecutionStepLimit(6145), codeB)
    verify(firstB, sourceB, 2048, 5)
    assert firstB.value.backend == PvmBackend.Interpreted, "retainedCompletionFairness.5"
    let queued = runtime.runtimeInfo
    assert queued.phase == NativePhase.Queued and queued.completions == 1, "retainedCompletionFairness.6"
    assert queued.submitted == 2 and queued.completed == 1 and queued.registered == 2, "retainedCompletionFairness.7"
    assert preparedNativeState(codeA).value == NativeState.Pending, "retainedCompletionFairness.8"
    assert preparedInfo(codeA).value.nativeFragments == 0, "retainedCompletionFairness.9"
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    assert runtime.runtimeInfo.completions == 2 and runtime.runtimeInfo.completed == 2, "retainedCompletionFairness.10"
    let readyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
    verify(readyB, sourceB, 2048, 5)
    assert readyB.value.backend == PvmBackend.Jit, "retainedCompletionFairness.11"
    assert preparedInfo(codeB).value.nativeFragments == 1, "retainedCompletionFairness.12"
    assert preparedInfo(codeB).value.nativeOperations == 4096, "retainedCompletionFairness.13"
    assert runtime.runtimeInfo.completions == 1, "retainedCompletionFairness.14"
    assert preparedNativeState(codeA).value == NativeState.Pending, "retainedCompletionFairness.15"
    let readyA = execute(sourceA, ExecutionStepLimit(6145), codeA)
    verify(readyA, sourceA, 2048)
    assert readyA.value.backend == PvmBackend.Jit, "retainedCompletionFairness.16"
    assert preparedInfo(codeA).value.nativeFragments == 1, "retainedCompletionFairness.17"
    assert preparedInfo(codeA).value.nativeOperations == 4096, "retainedCompletionFairness.18"
    assert runtime.runtimeInfo.completions == 0 and runtime.runtimeInfo.phase == NativePhase.Idle, "retainedCompletionFairness.19"
    codeA = default(PreparedProgram)
    codeB = default(PreparedProgram)
    assert runtime.runtimeInfo.registered == 0 and runtime.close(), "retainedCompletionFairness.20"
    verify(firstA, sourceA, 2048)
    verify(firstB, sourceB, 2048, 5)
    verify(readyA, sourceA, 2048)
    verify(readyB, sourceB, 2048, 5)

  proc parkedCompletionCapacity() =
    ## Four real parked images hold all credits; final drop unmaps before fifth/new-generation admission.
    if not nativePlatformSupported(): return
    let runtime = newNativeRuntime()
    assert launch(runtime), "parkedCompletionCapacity.1"
    let addends = [3'u8, 5, 3, 5, 5]
    var sources = default(array[5, Machine])
    var codes = default(array[5, PreparedProgram])
    var histories = default(array[5, StepResult])
    var retiredKey = default(NativeCompilerObservation)
    for index in 0..<5:
      # Independent decoded identities use their own matching immutable CPU/RAM source.
      sources[index] = input(loopOwner(addends[index]), 2048)
      codes[index] = prepared(sources[index].programOf.value, runtime)
    for index in 0..<4:
      # The one-shot gate makes each completed image observable without consuming its result.
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      histories[index] = execute(sources[index], ExecutionStepLimit(6145), codes[index])
      verify(histories[index], sources[index], 2048, addends[index])
      assert histories[index].value.backend == PvmBackend.Interpreted, "parkedCompletionCapacity.2"
      let key = waitNativeCompilerGate(runtime)
      assert key.hasImage, "parkedCompletionCapacity.3"
      if index == 0: retiredKey = key
      releaseNativeCompilerGate(runtime)
      assert runtime.runtimeInfo.completions == index+1, "parkedCompletionCapacity.4"
    histories[4] = execute(sources[4], ExecutionStepLimit(6145), codes[4])
    verify(histories[4], sources[4], 2048, 5)
    assert histories[4].value.backend == PvmBackend.Interpreted, "parkedCompletionCapacity.5"
    let full = runtime.runtimeInfo
    assert full.registered == 4 and full.completions == 4 and full.submitted == 4, "parkedCompletionCapacity.6"
    assert preparedNativeState(codes[4]).value == NativeState.Deferred, "parkedCompletionCapacity.7"
    codes[0] = default(PreparedProgram) # Synchronous completed-image retirement returns exactly one credit.
    assert runtime.runtimeInfo.registered == 3 and runtime.runtimeInfo.completions == 3, "parkedCompletionCapacity.8"
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    let retry = execute(sources[4], ExecutionStepLimit(6145), codes[4])
    verify(retry, sources[4], 2048, 5)
    assert retry.value.backend == PvmBackend.Interpreted, "parkedCompletionCapacity.9"
    let replacement = waitNativeCompilerGate(runtime)
    assert replacement.hasImage and replacement.slot == retiredKey.slot, "parkedCompletionCapacity.10"
    assert replacement.generation == retiredKey.generation+1 and replacement.ticket >
        retiredKey.ticket, "parkedCompletionCapacity.11"
    releaseNativeCompilerGate(runtime)
    assert runtime.runtimeInfo.registered == 4 and runtime.runtimeInfo.completions == 4, "parkedCompletionCapacity.12"
    assert runtime.runtimeInfo.submitted == 5 and runtime.runtimeInfo.completed == 5, "parkedCompletionCapacity.13"
    for index in 1..<5:
      # +5 in the replacement slot must never execute the physically retired +3 image.
      let ready = execute(sources[index], ExecutionStepLimit(6145), codes[index])
      verify(ready, sources[index], 2048, addends[index])
      assert ready.value.backend == PvmBackend.Jit, "parkedCompletionCapacity.14"
      assert preparedInfo(codes[index]).value.nativeFragments == 1, "parkedCompletionCapacity.15"
      assert preparedInfo(codes[index]).value.nativeOperations == 4096, "parkedCompletionCapacity.16"
      codes[index] = default(PreparedProgram)
    assert runtime.runtimeInfo.registered == 0 and runtime.runtimeInfo.completions == 0, "parkedCompletionCapacity.17"
    assert runtime.close(), "parkedCompletionCapacity.18"
    for index in 0..<5:
      # Every pre-retirement result still owns its original complete CPU/RAM/source history.
      verify(histories[index], sources[index], 2048, addends[index])

  proc seedSession(source: Machine, session: NativeSession): Machine =
    ## Existing checked frame/lease path exposes a real session for controlled stream invalidation.
    var admitted = prepareFlatPlan(source.programOf.value, GasCycleLimit(1000),
      defaultFlatLimits(), allowNative = false)
    assert admitted.error == FlatError.None, "seedSession.1"
    let plan = takeValue(admitted)
    var made = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
    assert made.error == FlatError.None, "seedSession.2"
    var frame = takeValue(made)
    frame.nativeSession = session
    beginNativeInvocation(session, 6145)
    runFlat(frame, 6145)
    assert frame.reason == StepError.None and frame.exit == StepExit.Halt and frame.remaining == 0, "seedSession.3"
    assert nativeSpanInfo(session).len == 2, "seedSession.4"
    finishNativeInvocation(session, settledNativeWork(frame, 6145))
    let captured = captureMachine(source.programOf.value, flatMemorySnapshot(frame), frame.info)
    assert captured.error == MachineError.None, "seedSession.5"
    captured.value

  proc cancelledClaimAndPublication() =
    ## Invalidate then final-drop a ticket-cleared running owner, before emission and with a real local image.
    if not nativePlatformSupported(): return
    for point in [NativeCompilerPoint.AfterClaim, NativeCompilerPoint.BeforePublish]:
      # Each schedule starts a fresh bounded runtime and preserves an unrelated +3 parked completion.
      let runtime = newNativeRuntime()
      assert launch(runtime), "cancelledClaimAndPublication.1"
      let sourceB = input(loopOwner(), 2048)
      var codeB = prepared(sourceB.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let historyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
      verify(historyB, sourceB, 2048)
      assert waitNativeCompilerGate(runtime).hasImage, "cancelledClaimAndPublication.2"
      releaseNativeCompilerGate(runtime)
      armNativeCompilerGate(runtime, point)
      let sourceA = input(loopOwner(), 2048)
      var session = newNativeSession(runtime)
      let historyA = seedSession(sourceA, session)
      verifyState(historyA, sourceA, 2048)
      let old = waitNativeCompilerGate(runtime)
      assert old.point == point and old.hasImage == (point == NativeCompilerPoint.BeforePublish), "cancelledClaimAndPublication.3"
      assert runtime.runtimeInfo.phase == NativePhase.Running and runtime.runtimeInfo.completions ==
          1, "cancelledClaimAndPublication.4"
      assert runtime.runtimeInfo.registered == 2 and runtime.runtimeInfo.completed == 1, "cancelledClaimAndPublication.5"
      invalidateNativeStream(session)
      assert nativeEpoch(session) == old.epoch+1 and nativeState(session) == NativeState.Deferred, "cancelledClaimAndPublication.6"
      session = default(NativeSession) # Ticket is already zero; row authority must still cancel/retire.
      assert runtime.runtimeInfo.registered == 2 and runtime.runtimeInfo.completions == 1, "cancelledClaimAndPublication.7"
      releaseNativeCompilerGate(runtime)
      waitNativeCompiler(runtime)
      assert runtime.runtimeInfo.registered == 1 and runtime.runtimeInfo.completions == 1, "cancelledClaimAndPublication.8"
      assert runtime.runtimeInfo.completed == 1 and runtime.runtimeInfo.submitted == 2, "cancelledClaimAndPublication.9"
      let replacementSource = input(loopOwner(5), 2048)
      var replacementCode = prepared(replacementSource.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let first = execute(replacementSource, ExecutionStepLimit(6145), replacementCode)
      verify(first, replacementSource, 2048, 5)
      let fresh = waitNativeCompilerGate(runtime)
      assert fresh.hasImage and fresh.slot == old.slot and fresh.generation == old.generation+1, "cancelledClaimAndPublication.10"
      assert fresh.ticket > old.ticket and runtime.runtimeInfo.completions == 2, "cancelledClaimAndPublication.11"
      releaseNativeCompilerGate(runtime)
      let ready = execute(replacementSource, ExecutionStepLimit(6145), replacementCode)
      verify(ready, replacementSource, 2048, 5)
      assert ready.value.backend == PvmBackend.Jit, "cancelledClaimAndPublication.12"
      assert preparedInfo(replacementCode).value.nativeOperations == 4096, "cancelledClaimAndPublication.13"
      assert runtime.runtimeInfo.completions == 1, "cancelledClaimAndPublication.14"
      let readyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
      verify(readyB, sourceB, 2048)
      assert readyB.value.backend == PvmBackend.Jit, "cancelledClaimAndPublication.15"
      assert runtime.runtimeInfo.completed == 2 and runtime.runtimeInfo.submitted == 3, "cancelledClaimAndPublication.16"
      codeB = default(PreparedProgram)
      replacementCode = default(PreparedProgram)
      assert runtime.runtimeInfo.registered == 0 and runtime.close(), "cancelledClaimAndPublication.17"
      verifyState(historyA, sourceA, 2048)
      verify(historyB, sourceB, 2048)
      verify(ready, replacementSource, 2048, 5)

  proc workerRetirementDrop() =
    ## Repeated invalidate/final drop during worker-owned disposal must retain the fourth credit until release.
    if not nativePlatformSupported(): return
    for point in [NativeCompilerPoint.AfterClaim, NativeCompilerPoint.BeforePublish]:
      # Exercise both cancelled-before-emission and real local-image retirement, not a scheduling guess.
      let runtime = newNativeRuntime()
      assert launch(runtime), "workerRetirementDrop.1"
      let sourceB = input(loopOwner(), 2048)
      var codeB = prepared(sourceB.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let historyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
      verify(historyB, sourceB, 2048)
      assert waitNativeCompilerGate(runtime).hasImage, "workerRetirementDrop.2"
      releaseNativeCompilerGate(runtime)
      let sourceC = input(loopOwner(), 16)
      let sourceD = input(loopOwner(5), 16)
      var codeC = prepared(sourceC.programOf.value, runtime)
      var codeD = prepared(sourceD.programOf.value, runtime)
      let historyC = execute(sourceC, ExecutionStepLimit(49), codeC)
      let historyD = execute(sourceD, ExecutionStepLimit(49), codeD)
      verify(historyC, sourceC, 16)
      verify(historyD, sourceD, 16, 5)
      assert runtime.runtimeInfo.registered == 3 and runtime.runtimeInfo.submitted == 1, "workerRetirementDrop.3"
      let sourceA = input(loopOwner(), 2048)
      var session = newNativeSession(runtime)
      armNativeCompilerGate(runtime, point)
      let historyA = seedSession(sourceA, session)
      verifyState(historyA, sourceA, 2048)
      let old = waitNativeCompilerGate(runtime)
      assert old.point == point and old.hasImage == (point == NativeCompilerPoint.BeforePublish), "workerRetirementDrop.4"
      invalidateNativeStream(session) # First cancellation clears the private ticket, not the row obligation.
      assert nativeEpoch(session) == old.epoch+1, "workerRetirementDrop.5"
      releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
      let retiring = waitNativeCompilerGate(runtime)
      assert retiring.point == NativeCompilerPoint.BeforeRetire, "workerRetirementDrop.6"
      assert retiring.slot == old.slot and retiring.generation == old.generation, "workerRetirementDrop.7"
      assert retiring.ticket == old.ticket and retiring.epoch == old.epoch, "workerRetirementDrop.8"
      assert retiring.hasImage == old.hasImage, "workerRetirementDrop.9"
      invalidateNativeStream(session) # Actual second public invalidation occurs with row Reclaiming.
      assert nativeEpoch(session) == old.epoch+2 and nativeState(session) == NativeState.Deferred, "workerRetirementDrop.10"
      session = default(NativeSession) # Actual final drop must mark Retiring, not assert overlapping host cleanup.
      assert runtime.runtimeInfo.registered == 4 and runtime.runtimeInfo.completions == 1, "workerRetirementDrop.11"
      assert runtime.runtimeInfo.phase == NativePhase.Running, "workerRetirementDrop.12"
      let sourceNew = input(loopOwner(5), 2048)
      var codeNew = prepared(sourceNew.programOf.value, runtime)
      let blocked = execute(sourceNew, ExecutionStepLimit(6145), codeNew)
      verify(blocked, sourceNew, 2048, 5)
      assert blocked.value.backend == PvmBackend.Interpreted, "workerRetirementDrop.13"
      assert preparedNativeState(codeNew).value == NativeState.Deferred, "workerRetirementDrop.14"
      assert runtime.runtimeInfo.submitted == 2 and runtime.runtimeInfo.completed == 1, "workerRetirementDrop.15"
      assert runtime.runtimeInfo.registered == 4, "workerRetirementDrop.16" # The fifth owner cannot borrow the not-yet-disposed credit.
      releaseNativeCompilerGate(runtime)
      waitNativeCompiler(runtime)
      assert runtime.runtimeInfo.registered == 3 and runtime.runtimeInfo.completions == 1, "workerRetirementDrop.17"
      assert runtime.runtimeInfo.submitted == 2 and runtime.runtimeInfo.completed == 1, "workerRetirementDrop.18"
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let retry = execute(sourceNew, ExecutionStepLimit(6145), codeNew)
      verify(retry, sourceNew, 2048, 5)
      let fresh = waitNativeCompilerGate(runtime)
      assert fresh.hasImage and fresh.slot == old.slot and fresh.generation == old.generation+1, "workerRetirementDrop.19"
      assert fresh.ticket > old.ticket and runtime.runtimeInfo.completions == 2, "workerRetirementDrop.20"
      releaseNativeCompilerGate(runtime)
      let ready = execute(sourceNew, ExecutionStepLimit(6145), codeNew)
      verify(ready, sourceNew, 2048, 5)
      assert ready.value.backend == PvmBackend.Jit, "workerRetirementDrop.21"
      assert preparedInfo(codeNew).value.nativeOperations == 4096, "workerRetirementDrop.22"
      let readyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
      verify(readyB, sourceB, 2048)
      assert readyB.value.backend == PvmBackend.Jit, "workerRetirementDrop.23"
      assert runtime.runtimeInfo.submitted == 3 and runtime.runtimeInfo.completed == 2, "workerRetirementDrop.24"
      codeB = default(PreparedProgram)
      codeC = default(PreparedProgram)
      codeD = default(PreparedProgram)
      codeNew = default(PreparedProgram)
      assert runtime.runtimeInfo.registered == 0 and runtime.runtimeInfo.completions == 0, "workerRetirementDrop.25"
      assert runtime.close(), "workerRetirementDrop.26"
      verifyState(historyA, sourceA, 2048)
      verify(historyB, sourceB, 2048)
      verify(historyC, sourceC, 16)
      verify(historyD, sourceD, 16, 5)
      verify(blocked, sourceNew, 2048, 5)
      verify(ready, sourceNew, 2048, 5)

  proc closeCompletionWindows() =
    ## Stop escapes queued/claimed/local-image gates, retires parked output, and preserves an installed survivor.
    if not nativePlatformSupported(): return
    for point in [NativeCompilerPoint.AfterPublish, NativeCompilerPoint.AfterClaim,
        NativeCompilerPoint.BeforePublish]:
      # C owns installed +3 code; A parks +5 code; B is stopped in the selected third-owner window.
      let runtime = newNativeRuntime()
      assert launch(runtime), "closeCompletionWindows.1"
      let sourceC = input(loopOwner(), 2048)
      var codeC = prepared(sourceC.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let firstC = execute(sourceC, ExecutionStepLimit(6145), codeC)
      verify(firstC, sourceC, 2048)
      let installedKey = waitNativeCompilerGate(runtime)
      assert installedKey.hasImage, "closeCompletionWindows.2"
      releaseNativeCompilerGate(runtime)
      let readyC = execute(sourceC, ExecutionStepLimit(6145), codeC)
      verify(readyC, sourceC, 2048)
      assert readyC.value.backend == PvmBackend.Jit, "closeCompletionWindows.3"
      let sourceA = input(loopOwner(5), 2048)
      var codeA = prepared(sourceA.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let historyA = execute(sourceA, ExecutionStepLimit(6145), codeA)
      verify(historyA, sourceA, 2048, 5)
      assert waitNativeCompilerGate(runtime).hasImage, "closeCompletionWindows.4"
      if point != NativeCompilerPoint.AfterPublish:
        # Otherwise keep A's AfterPublish gate blocking the worker while B queues behind parked A.
        releaseNativeCompilerGate(runtime)
        armNativeCompilerGate(runtime, point)
      let sourceB = input(loopOwner(), 2048)
      var codeB = prepared(sourceB.programOf.value, runtime)
      let historyB = execute(sourceB, ExecutionStepLimit(6145), codeB)
      verify(historyB, sourceB, 2048)
      assert historyB.value.backend == PvmBackend.Interpreted, "closeCompletionWindows.5"
      if point == NativeCompilerPoint.AfterPublish:
        assert runtime.runtimeInfo.phase == NativePhase.Queued, "closeCompletionWindows.6"
      else:
        let observed = waitNativeCompilerGate(runtime)
        assert observed.point == point, "closeCompletionWindows.7"
        assert observed.hasImage == (point == NativeCompilerPoint.BeforePublish), "closeCompletionWindows.8"
        assert runtime.runtimeInfo.phase == NativePhase.Running, "closeCompletionWindows.9"
      assert runtime.runtimeInfo.completions == 1 and runtime.runtimeInfo.registered == 3, "closeCompletionWindows.10"
      assert runtime.close() # No release/controller thread: stopping must bypass every armed gate., "closeCompletionWindows.11"
      let closed = runtime.runtimeInfo
      assert closed.phase == NativePhase.Idle and closed.completions == 0 and closed.active == 0, "closeCompletionWindows.12"
      assert closed.registered == 3 and closed.submitted == 3 and closed.completed == 2, "closeCompletionWindows.13"
      assert runtime.close() and not launch(runtime), "closeCompletionWindows.14"
      codeA = default(PreparedProgram)
      codeB = default(PreparedProgram)
      assert runtime.runtimeInfo.registered == 1 and not launch(runtime), "closeCompletionWindows.15"
      let closedC = execute(sourceC, ExecutionStepLimit(6145), codeC)
      verify(closedC, sourceC, 2048)
      assert closedC.value.backend == PvmBackend.Interpreted, "closeCompletionWindows.16"
      assert preparedInfo(codeC).value.nativeOperations == 4096, "closeCompletionWindows.17"
      assert preparedInfo(codeC).value.nativeCodeBytes > 0, "closeCompletionWindows.18"
      codeC = default(PreparedProgram) # Last installed image release finally permits a fresh namespace.
      assert runtime.runtimeInfo.registered == 0 and launch(runtime), "closeCompletionWindows.19"
      let sourceNew = input(loopOwner(5), 2048)
      var codeNew = prepared(sourceNew.programOf.value, runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let firstNew = execute(sourceNew, ExecutionStepLimit(6145), codeNew)
      verify(firstNew, sourceNew, 2048, 5)
      let fresh = waitNativeCompilerGate(runtime)
      assert fresh.hasImage and fresh.slot == installedKey.slot, "closeCompletionWindows.20"
      assert fresh.generation == installedKey.generation+1 and fresh.ticket > installedKey.ticket, "closeCompletionWindows.21"
      releaseNativeCompilerGate(runtime)
      let readyNew = execute(sourceNew, ExecutionStepLimit(6145), codeNew)
      verify(readyNew, sourceNew, 2048, 5)
      assert readyNew.value.backend == PvmBackend.Jit, "closeCompletionWindows.22"
      codeNew = default(PreparedProgram)
      assert runtime.runtimeInfo.registered == 0 and runtime.close(), "closeCompletionWindows.23"
      verify(firstC, sourceC, 2048)
      verify(readyC, sourceC, 2048)
      verify(historyA, sourceA, 2048, 5)
      verify(historyB, sourceB, 2048)
      verify(closedC, sourceC, 2048)
      verify(readyNew, sourceNew, 2048, 5)

proc runSharedAsync*() =
  ## Both ISA mains execute this same policy/lifetime/correctness contract on their supported host.
  diagnosticPhase("checkedReceipts")
  checkedReceipts()
  diagnosticPhase("closedHandleMoves")
  closedHandleMoves()
  when defined(pvmSharedAsyncWitness):
    diagnosticPhase("hostReceipts")
    hostReceipts()
    diagnosticPhase("staleStreamEpoch")
    staleStreamEpoch()
    diagnosticPhase("asyncLifecycle")
    asyncLifecycle()
    diagnosticPhase("retainedCompletionFairness")
    retainedCompletionFairness()
    diagnosticPhase("parkedCompletionCapacity")
    parkedCompletionCapacity()
    diagnosticPhase("cancelledClaimAndPublication")
    cancelledClaimAndPublication()
    diagnosticPhase("workerRetirementDrop")
    workerRetirementDrop()
    diagnosticPhase("closeCompletionWindows")
    closeCompletionWindows()
    diagnosticPhase("cancelledFinalDrop")
    cancelledFinalDrop()
    diagnosticPhase("readyReservations")
    readyReservations()
    diagnosticPhase("doneFinalDrop")
    doneFinalDrop()
  echo "PVM shared async passed"
