# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Metered host continuations retain one block charge, register replies and explicit shared budgets.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step

type HostContext = object ## Plain synchronous state retains only expected metadata and callback order.
  calls: uint64
  firstId, secondPc: uint64

proc framed(tail: openArray[byte]): seq[byte] =
  ## Literal instruction groups define exact opcode masks independently of the production decoder.
  var first = @[10'u8]
  for octet in tail: first.add(octet)
  let groups = [@[51'u8, 7, 7], first, @[100'u8, 137], @[10'u8, 13], @[100'u8, 138], @[50'u8, 0]]
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for instruction in groups:
    starts.add(code.len)
    for octet in instruction: code.add(octet)
  result = @[0'u8, 0, byte(code.len)]
  for octet in code: result.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or byte(1 shl (start mod 8))
  for octet in mask: result.add(octet)

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Host replies change only r8 and preserve the already-paid gas and immutable memory owner.
  assert suspension.exit == StepExit.Host and context.calls < 2
  let cpu = machineInfo(suspension.machine).value
  assert uint64(cpu.gas) == 7 and cpu.blockCharged
  assert uint64(cpu.registers[7]) == 7
  if context.calls == 0:
    assert uint64(suspension.hostCall) == context.firstId and uint64(cpu.pc) == 3
    assert uint64(cpu.registers[8]) == 77 and uint64(cpu.registers[9]) == 88
  else:
    assert uint64(suspension.hostCall) == 13 and uint64(cpu.pc) == context.secondPc
    assert uint64(cpu.registers[8]) == 41 and uint64(cpu.registers[9]) == 41
  inc context.calls
  var registers = cpu.registers
  registers[8] = RegisterValue(40+context.calls)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: memoryOf(suspension.machine).value)

for row in [(newSeq[byte](0), 0'u64), (@[0'u8], 0'u64), (@[127'u8], 127'u64),
    (@[128'u8], 0xffffffffffffff80'u64), (@[128'u8, 0], 128'u64),
    (@[0'u8, 128], 0xffffffffffff8000'u64), (@[255'u8, 255, 255, 127], 0x7fffffff'u64),
    (@[0'u8, 0, 0, 128], 0xffffffff80000000'u64),
    (@[255'u8, 255, 255, 255], 0xffffffffffffffff'u64)]:
  let program = decodeJamProgram(framed(row[0]), CodeAddress(0), ProgramByteLimit(64),
      JumpCountLimit(0)).value
  assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(106)).value) == 103
  let oneLess = blockGas(program, CodeAddress(0), GasCycleLimit(105))
  assert oneLess.error == GasError.CycleLimitExceeded
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[7] = RegisterValue(99)
  registers[8] = RegisterValue(77)
  registers[9] = RegisterValue(88)
  registers[10] = RegisterValue(89)
  let source = captureMachine(program, captureMemory([], PageLimit(0)).value,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(110), blockCharged: false,
        registers: registers)).value
  for scenario in 0..<4:
    var context = HostContext(calls: 0, firstId: row[1], secondPc: uint64(6+row[0].len))
    let steps = if scenario == 1: 5'u64 else: 6'u64
    let calls = if scenario == 2: 1'u64 elif scenario == 3: 0'u64 else: 2'u64
    let checked = executeWithHost(source, context, respond, ExecutionStepLimit(steps),
      HostCallLimit(calls), GasCycleLimit(106))
    if scenario == 0:
      assert checked.error == StepError.None and checked.value.exit == StepExit.Halt
      let final = machineInfo(checked.value.machine).value
      assert uint64(final.gas) == 7 and uint64(final.pc) == 0 and final.blockCharged
      for index in 0..<13:
        let expected = if index == 7: 7'u64 elif index == 8 or index == 10: 42'u64
          elif index == 9: 41'u64 else: uint64(registers[index])
        assert uint64(final.registers[index]) == expected
      assert context.calls == 2
    elif scenario == 1:
      assert checked.error == StepError.StepLimitExceeded and context.calls == 2
    else:
      assert checked.error == StepError.HostCallLimitExceeded and context.calls == calls
    for index in 0..<13:
      assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
    assert uint64(machineInfo(source).value.gas) == 110 and not machineInfo(
        source).value.blockCharged

echo "PVM metered host-resumption reference passed: 9"
