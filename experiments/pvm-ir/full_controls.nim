# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Admission, ownership, policy, reuse and fallible-host witnesses for complete prepared execution.
import std/[assertions, syncio, envvars]
import ../../src/pvm/[program, machine, gas]
import ../../src/codec/natural
import ../../build/pvm-ir-experiment/full_step as prepared

proc owner(): Program =
  ## Ecalli 7 followed by a dynamic return through r0; all instruction starts are explicit.
  let decoded = decodeJamProgram([0'u8, 0, 5, 10, 7, 50, 0, 0, 0x15], CodeAddress(0),
    ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

type
  Refusal {.pure.} = enum ## Domain-valued failures must not become guest execution exits.
    Stop
  Context = object ## Caller effects survive a typed failure while invocation state remains private.
    calls: int
    refuse: bool

proc callback(context: var Context, stopped: prepared.StepOutcome): prepared.HostResult[
    Refusal] {.raises: [].} =
  ## Continue once or deliberately fail after recording the external callback effect.
  inc context.calls
  if context.refuse: return prepared.hostFailure[Refusal](Refusal.Stop)
  let cpu = machineInfo(stopped.machine).value
  prepared.hostSuccess[Refusal](prepared.HostResponse(action: prepared.HostAction.Continue,
    gas: cpu.gas, registers: cpu.registers, memory: memoryOf(stopped.machine).value))

proc padded(size, stride: int): Program =
  ## Exact allocation/index ceilings use marked traps with bounded bitmap-delimited padding.
  assert size > 0 and stride > 0 and stride <= 24
  let natural = encode(JamNatural(size))
  var wire: seq[byte] = @[0'u8, 0'u8]
  for i in 0..<natural.len: wire.add(natural.bytes[i])
  for i in 0..<size: wire.add(0'u8)
  var mask = newSeq[byte]((size + 7) div 8)
  var pc = 0
  while pc < size:
    mask[pc div 8] = mask[pc div 8] or byte(1 shl (pc mod 8))
    pc += stride
  for item in mask: wire.add(item)
  let captured = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(2097152), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value

proc orphan(mode: prepared.PricingMode): prepared.PreparedInvocation =
  ## The returned invocation must retain code, prices, source CPU and memory after all local aliases retire.
  let programOwner = owner()
  let memory = captureMemory([], PageLimit(0)).value
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), registers: default(RegisterFile))
  info.registers[0] = RegisterValue(0xffff0000)
  let code = prepared.prepareExecution(programOwner, prepared.defaultPreparedLimits(mode)).value
  prepared.bindPrepared(code, memory, info).value

if getEnv("PVM_FULL_ASSERT_PROBE") == "1":
  assert false, "full prepared assertion control"
let guestOwner = owner()
let memory = captureMemory([], PageLimit(0)).value
var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), registers: default(RegisterFile))
info.registers[0] = RegisterValue(0xffff0000)
let source = captureMachine(guestOwner, memory, info).value
assert prepared.bindPrepared(default(prepared.PreparedExecution), source).error ==
    prepared.PreparedError.InvalidInput
assert prepared.executePrepared(default(prepared.PreparedInvocation), prepared.ExecutionStepLimit(
    1)).error == prepared.StepError.InvalidMachine
assert prepared.prepareExecution(default(Program), prepared.defaultPreparedLimits()).error ==
    prepared.PreparedError.InvalidProgram
for mode in [prepared.PricingMode.Lazy, prepared.PricingMode.Complete]:
  # Both modes share the same owner/admission bounds and complete host semantics.
  var limits = prepared.defaultPreparedLimits(mode)
  var short = limits
  short.codeBytes = prepared.PreparedCodeLimit(0)
  assert prepared.prepareExecution(guestOwner, short).error == prepared.PreparedError.CodeLimit
  short = limits
  short.instructions = prepared.PreparedOperationLimit(0)
  assert prepared.prepareExecution(guestOwner, short).error ==
      prepared.PreparedError.InstructionLimit
  short = limits
  short.bytes = prepared.PreparedPayloadLimit(0)
  assert prepared.prepareExecution(guestOwner, short).error == prepared.PreparedError.PriceLimit
  short = limits
  short.blocks = prepared.PreparedBlockLimit(0)
  assert prepared.prepareExecution(guestOwner, short).error == prepared.PreparedError.PriceLimit
  short = limits
  short.cycles = GasCycleLimit(0)
  let refused = prepared.prepareExecution(guestOwner, short)
  if mode == prepared.PricingMode.Complete:
    # Eager policy prices every block; zero simulation work is a construction refusal.
    assert refused.error == prepared.PreparedError.PriceCycleLimit
  else:
    # Lazy policy admits the owner and reports the local simulation error only on reaching the block.
    assert refused.error == prepared.PreparedError.None
    let input = prepared.bindPrepared(refused.value, source).value
    assert prepared.executePrepared(input, prepared.ExecutionStepLimit(1)).error ==
        prepared.StepError.GasCycleLimitExceeded
  let code = prepared.prepareExecution(guestOwner, limits).value
  let initial = prepared.preparedInfo(code).value
  assert initial.instructions == 3
  assert initial.payloadBytes == initial.codeBytes * 10 + initial.instructions * uint64(sizeof(
      ProgramResult[Instruction]))
  assert prepared.bindPrepared(code, captureMachine(owner(), memory, info).value).error ==
      prepared.PreparedError.WrongOwner
  assert prepared.bindPrepared(code, default(Machine)).error == prepared.PreparedError.InvalidInput
  let invocation = prepared.bindPrepared(code, source).value
  assert prepared.stepOnce(invocation).value.exit == prepared.StepExit.Host
  assert prepared.stepRegisters(invocation).error == prepared.StepError.UnsupportedInstruction
  assert prepared.executePrepared(invocation, prepared.ExecutionStepLimit(0)).error ==
      prepared.StepError.StepLimitExceeded
  for refuse in [true, false]:
    # Every fresh context reuses code, never a previous call's CPU, attempt or dispatch state.
    var context = Context(calls: 0, refuse: refuse)
    let done = prepared.executeWithHost(invocation, context, callback,
      prepared.ExecutionStepLimit(10), prepared.HostCallLimit(1))
    assert context.calls == 1
    if refuse:
      assert done.error == prepared.HostExecutionError.HostFailure
      assert done.hostError == Refusal.Stop
    else:
      assert done.error == prepared.HostExecutionError.None
      assert done.value.exit == prepared.StepExit.Halt
  let final = prepared.preparedInfo(code).value
  assert final.pricedBlocks <= final.blocks
  assert uint64(machineInfo(source).value.gas) == 10000
  assert uint64(machineInfo(source).value.pc) == 0
  var unused = Context(calls: 0, refuse: false)
  let limited = prepared.executeWithHost(invocation, unused, callback,
    prepared.ExecutionStepLimit(10), prepared.HostCallLimit(0))
  assert limited.error == prepared.HostExecutionError.ExecutionFailure
  assert limited.executionError == prepared.StepError.HostCallLimitExceeded
  assert unused.calls == 0
  # A copied immutable complete plan or exclusively used lazy handle remains reusable after other handles retire.
  let again = prepared.bindPrepared(code, memory, info).value
  assert prepared.stepOnce(again).value.exit == prepared.StepExit.Host
  echo "POLICY,", ord(mode), ",", final.payloadBytes, ",", final.pricedBlocks

for mode in [prepared.PricingMode.Lazy, prepared.PricingMode.Complete]:
  # Exercise the highest uint16 one-based record index and the exact one-MiB code ceiling.
  let limits = prepared.defaultPreparedLimits(mode)
  let maximumRecords = prepared.prepareExecution(padded(65535, 1), limits)
  assert maximumRecords.error == prepared.PreparedError.None
  assert prepared.preparedInfo(maximumRecords.value).value.instructions == 65535
  assert prepared.prepareExecution(padded(65536, 1), limits).error ==
      prepared.PreparedError.InstructionLimit
  let maximumCode = prepared.prepareExecution(padded(1048576, 17), limits)
  assert maximumCode.error == prepared.PreparedError.None
  let statistics = prepared.preparedInfo(maximumCode.value).value
  assert statistics.codeBytes == 1048576
  var exact = limits
  exact.bytes = prepared.PreparedPayloadLimit(statistics.payloadBytes)
  assert prepared.prepareExecution(padded(1048576, 17), exact).error == prepared.PreparedError.None
  exact.bytes = prepared.PreparedPayloadLimit(uint64(exact.bytes) - 1)
  assert prepared.prepareExecution(padded(1048576, 17), exact).error ==
      prepared.PreparedError.PriceLimit
  assert prepared.prepareExecution(padded(1048577, 17), limits).error ==
      prepared.PreparedError.CodeLimit
  let maximumInput = prepared.bindPrepared(maximumRecords.value, memory, info).value
  assert prepared.executePrepared(maximumInput, prepared.ExecutionStepLimit(1)).value.exit ==
      prepared.StepExit.Panic
  assert prepared.stepOnce(orphan(mode)).value.exit == prepared.StepExit.Host
  # A single immutable code/pricing handle survives a two-page atomic fault, repair and prepaid retry.
  let storeOwner = decodeJamProgram([0'u8, 0, 4, 123, 0x78, 50, 0, 5],
    CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
  let code = prepared.prepareExecution(storeOwner, limits).value
  let firstPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite, bytes: default(
      array[4096, byte]))
  let initialMemory = captureMemory([firstPage], PageLimit(2)).value
  var cpu = info
  cpu.registers[7] = RegisterValue(0x10ffc)
  cpu.registers[8] = RegisterValue(0x8877665544332211'u64)
  let original = prepared.bindPrepared(code, initialMemory, cpu).value
  let stopped = prepared.executePrepared(original, prepared.ExecutionStepLimit(10)).value
  assert stopped.exit == prepared.StepExit.Fault
  assert uint64(uint32(stopped.faultPage)) == 0x11000
  let frozen = memoryOf(stopped.machine).value
  for value in pageImage(frozen, PageIndex(16)).value.bytes: assert value == 0
  let secondPage = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite, bytes: default(
      array[4096, byte]))
  let repaired = withPage(frozen, secondPage).value
  let prior = machineInfo(stopped.machine).value
  assert prior.blockCharged and uint64(prior.gas) < uint64(cpu.gas)
  let retry = prepared.bindPrepared(code, repaired, prior).value
  let finished = prepared.executePrepared(retry, prepared.ExecutionStepLimit(10)).value
  assert finished.exit == prepared.StepExit.Halt
  assert uint64(machineInfo(finished.machine).value.gas) == uint64(prior.gas)
  assert uint64(load(memoryOf(finished.machine).value, MemoryAddress(0x10ffc), AccessWidth(
      8)).value) == 0x8877665544332211'u64
  assert prepared.executePrepared(original, prepared.ExecutionStepLimit(10)).value.exit ==
      prepared.StepExit.Fault
  for value in pageImage(initialMemory, PageIndex(16)).value.bytes: assert value == 0
  echo "BOUNDARY,", ord(mode), ",", statistics.codeBytes, ",", statistics.instructions, ",",
      statistics.payloadBytes

# A zero-cycle lazy policy may execute a prepaid block without inventing a preparation-time refusal.
var prepaidInfo = info
prepaidInfo.blockCharged = true
var zeroLimits = prepared.defaultPreparedLimits()
zeroLimits.cycles = GasCycleLimit(0)
let zeroCode = prepared.prepareExecution(guestOwner, zeroLimits).value
let prepaid = prepared.bindPrepared(zeroCode, memory, prepaidInfo).value
assert prepared.stepOnce(prepaid).value.exit == prepared.StepExit.Host
assert prepared.preparedInfo(zeroCode).value.pricedBlocks == 0

echo "FULL,admission-ownership-host-policies-passed"
