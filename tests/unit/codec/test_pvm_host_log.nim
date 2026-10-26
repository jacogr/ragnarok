# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JIP-1 witnesses bind gas, atomic diagnostic output, full-width memory and real guest continuation.

import std/[assertions, syncio]
import ../../../src/pvm/[machine, program, step, gas, host_log]

proc collect(lines: var seq[string], line: string) {.raises: [].} =
  ## Retain each complete record so invalid reads cannot hide a partial sink invocation.
  lines.add(line)

proc memory(): Memory =
  ## Adjacent RO/RW pages support cross-page strings; inaccessible and top-address pages test boundaries.
  var first = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
  first.bytes[0] = byte('t')
  first.bytes[4095] = byte('a')
  var second = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)
  second.bytes[0] = byte('b')
  second.bytes[1] = 10
  second.bytes[2] = 27
  second.bytes[3] = 0
  second.bytes[4] = 34
  second.bytes[5] = 92
  second.bytes[6] = 255
  var last = PageImage(index: PageIndex(1048575), access: PageAccess.ReadOnly)
  last.bytes[4095] = byte('z')
  captureMemory([first, second, PageImage(index: PageIndex(19), access: PageAccess.Inaccessible),
    last], PageLimit(4)).value

proc registers(): RegisterFile =
  ## Sentinels prove only r7 changes; original level must be logged before WHAT replaces it.
  result = default(RegisterFile)
  for index in 0..<13:
    result[index] = RegisterValue(uint64(100+index))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(2)
  result[8] = RegisterValue(65536)
  result[9] = RegisterValue(1)
  result[10] = RegisterValue(69631)
  result[11] = RegisterValue(2)

proc checked(regs: RegisterFile, mem: Memory, credit: uint64, expected: seq[string]) =
  ## Independent literal gas and register expectations cover every response, including silent filtering.
  var lines: seq[string] = @[]
  let reply = logHostResponse(MachineGas(credit), regs, mem, lines, collect)
  assert lines == expected
  assert reply.action == (if credit < 10: HostAction.OutOfGas else: HostAction.Continue)
  assert uint64(reply.gas) == (if credit < 10: 0'u64 else: credit-10)
  assert uint64(reply.gasDeficit) == 0
  for index in 0..<13:
    let wanted = if index == 7: high(uint64)-1 else: uint64(regs[index])
    assert uint64(reply.registers[index]) == wanted
  if mem.pageImage(PageIndex(16)).error == MachineError.None:
    # Every path retains the caller's bytes and permissions in both immutable owners.
    assert reply.memory.pageImage(PageIndex(16)).value.bytes == mem.pageImage(PageIndex(
        16)).value.bytes
    assert reply.memory.pageImage(PageIndex(16)).value.access == PageAccess.ReadOnly

let mem = memory()
let regs = registers()
for credit in 0'u64..11:
  # Exhaustion never reads/outputs, while exact funding still returns a completed WHAT response.
  var expected: seq[string] = @[]
  if credit >= 10:
    expected.add("JIP1 level=2 target=\"t\" message=\"ab\"") # Only funded calls may emit.
  checked(regs, mem, credit, expected)
for level in [0'u64, 1, 2, 3, 4, 5, high(uint64)]:
  var selected = regs
  selected[7] = RegisterValue(level)
  checked(selected, mem, 20, @["JIP1 level=" & $level & " target=\"t\" message=\"ab\""])
block:
  var selected = regs
  selected[10] = RegisterValue(69632)
  selected[11] = RegisterValue(7)
  checked(selected, mem, 10, @["JIP1 level=2 target=\"t\" message=\"b\\x0a\\x1b\\x00\\x22\\x5c\\xff\""])
for pointer in [0'u64, 1, high(uint64)]:
  # Absence differs from an empty present target; empty ranges do not dereference high pointers.
  var selected = regs
  selected[8] = RegisterValue(pointer)
  selected[9] = RegisterValue(0)
  selected[10] = RegisterValue(high(uint64))
  selected[11] = RegisterValue(0)
  let target = if pointer == 0: "null" else: "\"\""
  checked(selected, mem, 10, @["JIP1 level=2 target=" & target & " message=\"\""])
for register in [8, 10]:
  for pointer in [0'u64, 73728, 77824, 0xffffffff'u64, 0x100000000'u64, high(uint64)]:
    # Missing/inaccessible pages, end-of-domain overlap and full-width addresses suppress the whole record.
    var selected = regs
    selected[register] = RegisterValue(pointer)
    selected[register+1] = RegisterValue(2)
    checked(selected, mem, 10, @[])
  for length in [4097'u64, high(uint64)]:
    # The display ceiling is independent of range arithmetic and never refuses guest execution.
    var selected = regs
    selected[register+1] = RegisterValue(length)
    checked(selected, mem, 10, @[])
block:
  var selected = regs
  selected[10] = RegisterValue(0xffffffff'u64)
  selected[11] = RegisterValue(1)
  checked(selected, mem, 10, @["JIP1 level=2 target=\"t\" message=\"z\""])
checked(regs, default(Memory), 10, @[])
checked(regs, default(Memory), 0, @[])
block:
  # Both fields can reach their independent ceiling; escaping remains bounded at four bytes per octet.
  var selected = regs
  selected[8] = RegisterValue(69632)
  selected[9] = RegisterValue(4096)
  selected[10] = RegisterValue(69632)
  selected[11] = RegisterValue(4096)
  var lines: seq[string] = @[]
  let reply = logHostResponse(MachineGas(10), selected, mem, lines, collect)
  assert reply.action == HostAction.Continue and lines.len == 1
  assert lines[0].len <= 2*4*4096+100
  assert '\n' notin lines[0] and '\r' notin lines[0]

proc dispatch(lines: var seq[string], stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Test a genuine host suspension, not a fabricated snapshot or direct response application.
  assert uint64(stopped.hostCall) == 100
  let cpu = stopped.machine.machineInfo.value
  logHostResponse(cpu.gas, cpu.registers, stopped.machine.memoryOf.value, lines, collect)

let code = decodeProgram([0'u8, 0, 4, 10, 100, 50, 0, 5], CodeAddress(0),
  ProgramByteLimit(8), JumpCountLimit(0)).value
for credit in [9'u64, 10, 11]:
  # Prepaid code resumes to the real halt sentinel only if the host's own fixed price is affordable.
  let source = captureMachine(code, mem, MachineInfo(pc: CodeAddress(0), gas: MachineGas(credit),
    blockCharged: true, registers: regs)).value
  var lines: seq[string] = @[]
  let done = executeWithHost(source, lines, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
    GasCycleLimit(0)).value
  assert done.exit == (if credit < 10: StepExit.OutOfGas else: StepExit.Halt)
  assert lines.len == (if credit < 10: 0 else: 1)
  assert uint64(done.machine.machineInfo.value.registers[7]) == high(uint64)-1
  assert uint64(source.machineInfo.value.gas) == credit

echo "PVM host log passed"
