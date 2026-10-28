# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-source forced interpretation, native policy, warm reuse/hosts and cross-policy cache refusal.
import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/internal/handler_stream as pvm_handler_stream

type Context = object ## Callbacks only observe copied snapshots and retain no invocation addresses.
  calls: int
  forced: bool

proc source(): Machine =
  ## Literal arithmetic spans on both sides of a host call contain genuine supported native fragments.
  let parts = [@[51'u8, 7, 5], @[51'u8, 8, 3], @[200'u8, 0x87, 9], @[200'u8, 0x87, 10], @[10'u8, 2],
      @[51'u8, 8, 4], @[200'u8, 0x87, 9], @[200'u8, 0x87, 10], @[200'u8, 0x87, 11], @[50'u8, 0]]
  var code: seq[byte] = @[]
  var marks: seq[int] = @[]
  for part in parts:
    marks.add(code.len)
    for octet in part: code.add(octet)
  assert code.len < 128, "policy: code.len < 128"
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var bitmap = newSeq[byte]((code.len+7) div 8)
  for mark in marks: bitmap[mark div 8] = bitmap[mark div 8] or (1'u8 shl (mark mod 8))
  for octet in bitmap: raw.add(octet)
  let decoded = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "policy: decoded.error == ProgramError.None"
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  captureMachine(decoded.value, captureMemory([], PageLimit(1)).value,
      MachineInfo(pc: CodeAddress(0), gas: MachineGas(high(uint64)), registers: registers)).value

proc respond(context: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## A host resume cannot activate native handlers in a forced-interpreted prepared owner.
  inc context.calls
  if context.forced: assert suspension.backend == PvmBackend.Interpreted
  else:
    when defined(arm64) and not defined(pvmArm64JitRefuse):
      assert suspension.backend == PvmBackend.Jit
    else:
      assert suspension.backend == PvmBackend.Interpreted
  let info = machineInfo(suspension.machine).value
  HostResponse(action: HostAction.Continue, gas: info.gas, registers: info.registers,
    memory: memoryOf(suspension.machine).value)

let original = source()
let code = programOf(original).value
let limits = defaultPreparedLimits(GasCycleLimit(1000))
let forced = newPreparedProgram(code, limits, PvmBackend.Interpreted).value
let accelerated = newPreparedProgram(code, limits, PvmBackend.Jit).value
assert preparedInfo(forced).value.backend == PvmBackend.Interpreted, "policy: preparedInfo(forced).value.backend == PvmBackend.Interpreted"
assert preparedInfo(accelerated).value.backend == PvmBackend.Jit, "policy: preparedInfo(accelerated).value.backend == PvmBackend.Jit"
let automatic = newPreparedProgram(code, limits).value
assert preparedInfo(automatic).value.backend == DefaultPvmBackend, "policy: preparedInfo(automatic).value.backend == DefaultPvmBackend"
for invocation in 0..<3:
  var plain = Context(forced: true)
  var native = default(Context)
  let left = executeWithHost(original, plain, respond, ExecutionStepLimit(10), HostCallLimit(1), forced)
  let right = executeWithHost(original, native, respond, ExecutionStepLimit(10), HostCallLimit(1), accelerated)
  assert left.error == StepError.None and right.error == StepError.None, "policy: left.error == StepError.None and right.error == StepError.None"
  assert left.value.exit == StepExit.Halt and right.value.exit == left.value.exit, "policy: left.value.exit == StepExit.Halt and right.value.exit == left.value.exit"
  assert plain.calls == 1 and native.calls == 1, "policy: plain.calls == 1 and native.calls == 1"
  let expected = machineInfo(left.value.machine).value
  let actual = machineInfo(right.value.machine).value
  assert expected.pc == actual.pc and expected.gas == actual.gas, "policy: expected.pc == actual.pc and expected.gas == actual.gas"
  assert expected.gasDeficit == actual.gasDeficit and expected.blockCharged == actual.blockCharged, "policy: expected.gasDeficit == actual.gasDeficit and expected.blockCharged == actual.blockCharged"
  assert expected.registers == actual.registers, "policy: expected.registers == actual.registers"
  assert uint64(actual.registers[9]) == 9, "policy: uint64(actual.registers[9]) == 9"
  let info = preparedInfo(forced).value
  assert info.nativeFragments == 0 and info.nativeCalls == 0 and info.nativeOperations == 0, "policy: info.nativeFragments == 0 and info.nativeCalls == 0 and info.nativeOperations == 0"
  assert left.value.backend == PvmBackend.Interpreted, "policy: left.value.backend == PvmBackend.Interpreted"
  when defined(arm64) and not defined(pvmArm64JitRefuse):
    assert right.value.backend == PvmBackend.Jit
  else:
    assert right.value.backend == PvmBackend.Interpreted

let nativeInfo = preparedInfo(accelerated).value
when defined(arm64) and not defined(pvmArm64JitRefuse):
  assert nativeInfo.jitBuilt and nativeInfo.jitPlatformSupported, "policy: nativeInfo.jitBuilt and nativeInfo.jitPlatformSupported"
  assert nativeInfo.nativeFragments > 0 and nativeInfo.nativeCalls > 0 and
      nativeInfo.nativeOperations > 0, "policy: nativeInfo.nativeFragments > 0 and nativeInfo.nativeCalls > 0 and nativeInfo.nativeOperations > 0"
else:
  assert nativeInfo.nativeCalls == 0 and nativeInfo.nativeOperations == 0, "policy: nativeInfo.nativeCalls == 0 and nativeInfo.nativeOperations == 0"

# Exact immutable plan identities reject both transfer directions, even when only one side has emitted native code.
for allowNative in [false, true]:
  var admitted = prepareFlatPlan(code, GasCycleLimit(1000), defaultFlatLimits(), allowNative)
  var other = prepareFlatPlan(code, GasCycleLimit(1000), defaultFlatLimits(), not allowNative)
  assert admitted.error == FlatError.None and other.error == FlatError.None, "policy: admitted.error == FlatError.None and other.error == FlatError.None"
  let firstPlan = takeValue(admitted)
  let secondPlan = takeValue(other)
  var firstMade = prepareFlatMemoryFrame(firstPlan, memoryOf(original).value, machineInfo(
      original).value)
  var secondMade = prepareFlatMemoryFrame(secondPlan, memoryOf(original).value, machineInfo(
      original).value)
  assert firstMade.error == FlatError.None and secondMade.error == FlatError.None, "policy: firstMade.error == FlatError.None and secondMade.error == FlatError.None"
  var first = takeValue(firstMade)
  var second = takeValue(secondMade)
  runFlat(first, 10)
  assert first.reason == StepError.None and first.exit == StepExit.Host, "policy: first.reason == StepError.None and first.exit == StepExit.Host"
  var transferred = takeFlatStream(first)
  restoreFlatStream(second, transferred)
  runFlat(second, 10)
  assert second.reason == StepError.InvalidPreparedProgram, "policy: second.reason == StepError.InvalidPreparedProgram"
stdout.writeLine("PASS runtime PVM policy")
