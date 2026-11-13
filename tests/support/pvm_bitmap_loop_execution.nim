# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Qualify a relocated bitmap scan through the public owner, worker and checked exits.

import std/assertions
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/native_pipeline

const bitmapBase = 32'u64*4096

proc bitmapOwner(): Program =
  ## Entry PC4 falls into the scan at PC5. PCs51,53,58 halt, reset and trap respectively.
  let wire = [0'u8, 0, 59, 0, 0, 0, 0, 1,
    149, 0xbb, 1, 200, 0xc5, 5, 170, 0xb7, 40,
    132, 0xbc, 1, 81, 0x0c, 244,
    152, 0xbc, 1, 174, 0xac, 30,
    152, 0xb6, 7, 174, 0x96, 29,
    151, 0x66, 3, 200, 0x86, 6, 130, 0x66, 133, 0x66, 255,
    208, 0xc6, 12, 132, 0xcc, 1, 40, 212,
    50, 0, 51, 4, 42, 50, 0, 0,
    63, 73, 146, 36, 73, 73, 42, 5]
  let decoded = decodeJamProgram(wire, CodeAddress(4), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "bitmap wire decodes"
  decoded.value

proc bitmapInput(owner: Program, memory: Memory, base = bitmapBase, finish = 1024'u64,
    midpoint = 8192'u64, lastWord = 512'u64, gas = 1000000'u64, pc = 4'u64): Machine =
  ## Use fresh CPU values with an independent canary in every untouched lane.
  var registers = default(RegisterFile)
  for slot in 0..<13: registers[slot] = RegisterValue(uint64(slot)*111)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[6] = RegisterValue(0)
  registers[7] = RegisterValue(finish)
  registers[8] = RegisterValue(base)
  registers[9] = RegisterValue(lastWord)
  registers[10] = RegisterValue(midpoint)
  registers[11] = RegisterValue(0)
  registers[12] = RegisterValue(0)
  let captured = captureMachine(owner, memory, MachineInfo(pc: CodeAddress(pc),
    gas: MachineGas(gas), registers: registers))
  assert captured.error == MachineError.None, "bitmap machine captures"
  captured.value

proc compareBitmap(source: Machine, native, checked: PreparedProgram, budget: uint64): StepResult =
  ## Compare the full public result and page against a separate checked owner.
  let expected = execute(source, ExecutionStepLimit(budget), checked)
  result = execute(source, ExecutionStepLimit(budget), native)
  assert result.error == expected.error, "bitmap native/local status parity"
  if result.error != StepError.None: return
  let actual = result.value
  let reference = expected.value
  assert actual.exit == reference.exit, "bitmap exit parity"
  if reference.exit == StepExit.Fault:
    assert actual.faultPage == reference.faultPage, "bitmap checked fallback fault page"
  assert machineInfo(actual.machine).value == machineInfo(reference.machine).value,
    "bitmap registers, PC, paid state and gas parity"
  let actualMemory = memoryOf(actual.machine).value
  let expectedMemory = memoryOf(reference.machine).value
  assert pageIndices(actualMemory).value == pageIndices(expectedMemory).value
  assert pageImage(actualMemory, PageIndex(32)).value == pageImage(expectedMemory, PageIndex(32)).value

proc runBitmapLoopExecution*() =
  ## Publish through the production worker, then exercise checked refusals with a ready image.
  let runtime = newNativeRuntime()
  try:
    assert runtime.start(), "bitmap compiler starts"
  except:
    assert false, "bitmap compiler startup failed"
  block:
    let owner = bitmapOwner()
    let limits = defaultPreparedLimits(GasCycleLimit(1000))
    let admitted = newPreparedProgram(owner, limits, PvmBackend.Jit, runtime)
    let interpreted = newPreparedProgram(owner, limits, PvmBackend.Interpreted)
    assert admitted.error == PreparationError.None and interpreted.error == PreparationError.None
    let native = admitted.value
    let checked = interpreted.value
    var page = PageImage(index: PageIndex(32), access: PageAccess.ReadWrite)
    for i in 0..<4096: page.bytes[i] = byte((i*17+29) and 255)
    let mapped = captureMemory([page], PageLimit(1))
    assert mapped.error == MachineError.None, "bitmap memory captures"
    let memory = mapped.value
    let suffix = bitmapInput(owner, memory, pc = 32)
    assert compareBitmap(suffix, native, checked, 7).error == StepError.StepLimitExceeded,
      "a short suffix caches the read backedge before its successor branches execute"
    assert runtime.runtimeInfo.submitted == 0
    let source = bitmapInput(owner, memory)
    let first = compareBitmap(source, native, checked, 20000)
    assert first.error == StepError.None and first.value.exit == StepExit.Halt and
      first.value.backend == PvmBackend.Interpreted, "bitmap discovery executes checked"
    waitNativeCompiler(runtime)
    when defined(pvmArm64JitRefuse) or defined(pvmX86JitRefuse):
      let refused = compareBitmap(source, native, checked, 20000)
      assert refused.error == StepError.None and refused.value.backend == PvmBackend.Interpreted
    else:
      let reused = compareBitmap(source, native, checked, 20000)
      assert reused.error == StepError.None and reused.value.backend == PvmBackend.Jit
      assert preparedInfo(native).value.nativeOperations == 10750, "all five original bitmap blocks execute natively"
      let reset = compareBitmap(bitmapInput(owner, memory, midpoint = 2), native, checked, 20000)
      assert reset.error == StepError.None and reset.value.exit == StepExit.Halt and
        uint64(machineInfo(reset.value.machine).value.registers[4]) == 42
      let trap = compareBitmap(bitmapInput(owner, memory, lastWord = 0), native, checked, 20000)
      assert trap.error == StepError.None and trap.value.exit == StepExit.Panic
      let fault = compareBitmap(bitmapInput(owner, memory, base = bitmapBase+4096), native, checked, 20000)
      assert fault.error == StepError.None and fault.value.exit == StepExit.Fault and
        fault.value.faultPage == PageAddress(bitmapBase+4096)
      let low = compareBitmap(bitmapInput(owner, memory, base = 0), native, checked, 20000)
      assert low.error == StepError.None and low.value.exit == StepExit.Panic
      let edge = bitmapInput(owner, memory, base = 0x100000000'u64+bitmapBase+4088, finish = 128)
      let wrapped = compareBitmap(edge, native, checked, 20000)
      assert wrapped.error == StepError.None and wrapped.value.exit == StepExit.Halt
      for budget in 4100'u64..4120:
        assert compareBitmap(source, native, checked, budget).error == StepError.StepLimitExceeded
      # Cross each first-pass price boundary with an independently obtained whole-block price.
      var spent = 0'u64
      for pc in [4'u64, 5, 14, 20, 26, 32]:
        let cost = blockGas(owner, CodeAddress(pc), GasCycleLimit(1000))
        assert cost.error == GasError.None
        spent += uint64(cost.value)
        for gas in spent-1..spent+1:
          let limited = bitmapInput(owner, memory, gas = gas)
          let stopped = compareBitmap(limited, native, checked, 20000)
          assert stopped.error == StepError.None and stopped.value.exit == StepExit.OutOfGas
    assert runtime.runtimeInfo.submitted == 1 and runtime.runtimeInfo.completed == 1,
      "bitmap owner uses one original primary credit"
  assert runtime.runtimeInfo.registered == 0 and runtime.close(), "bitmap owner returns its credit"
