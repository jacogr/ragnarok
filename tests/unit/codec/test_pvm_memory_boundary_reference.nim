# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay executed pinned PolkaVM last-byte witnesses without linking or running Rust.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, step]

proc word(data: string, at, width: int): uint64 =
  ## Read a little-endian field only after the complete fixed corpus extent is checked.
  result = 0
  for i in 0..<width:
    # Test-format decoding is independent of the production program decoder.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc owner(op: byte, address: uint64): Program =
  ## Mark only the byte operation and trailing trap, with a literal four-byte address.
  var blob = @[0'u8, 0, 7, op, 7]
  for i in 0..<4:
    # The fixed address width sign-extends high addresses through normal guest decoding.
    blob.add(byte((address shr (8 * i)) and 255))
  blob.add(0)
  blob.add(65)
  let decoded = decodeProgram(blob, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

var data = ""
try:
  # Frozen reference bytes are mandatory; unavailable fixture input is a setup failure.
  data = readFile(getEnv("RAGNAROK_PVM_MEMORY_BOUNDARY"))
except:
  quit 2
assert data.len == 312 and data[0..7] == "PVMMEM01" and word(data, 8, 4) == 12
for row in 0..<12:
  # Each record contains address, mapping, opcode, exit, fault page, A0 and two tail bytes.
  let at = 12 + row * 25
  let address = word(data, at, 8)
  let mapping = byte(data[at + 8])
  let op = byte(data[at + 9])
  let exit = byte(data[at + 10])
  let expectedFault = word(data, at + 11, 4)
  let expectedA0 = word(data, at + 15, 8)
  assert address in [0xfffffffe'u64, 0xffffffff'u64]
  assert mapping <= 2 and op in [52'u8, 59'u8] and exit <= 2
  let access = if mapping == 0: PageAccess.Inaccessible
    elif mapping == 1: PageAccess.ReadWrite else: PageAccess.ReadOnly
  var image = PageImage(index: PageIndex(0xfffff), access: access,
    bytes: default(array[4096, byte]))
  for i in 0..<4096:
    # Retained inaccessible bytes also detect accidental writes on an absent-page fault.
    image.bytes[i] = 7
  let memory = captureMemory([image], PageLimit(1)).value
  var regs = default(RegisterFile)
  regs[0] = RegisterValue(0xffff0000'u64)
  regs[7] = RegisterValue(99)
  let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: true,
    registers: regs)
  let source = captureMachine(owner(op, address), memory, initial).value
  let answer = stepMemory(source, GasCycleLimit(0))
  assert answer.error == StepError.None
  let outcome = answer.value
  let expectedExit = if exit == 0: StepExit.Continued
    elif exit == 1: StepExit.Panic else: StepExit.Fault
  assert outcome.exit == expectedExit
  if exit == 2:
    # The reference's exact physical fault address must survive guest stepping.
    assert uint64(uint32(outcome.faultPage)) == expectedFault
  else:
    assert expectedFault == 0
  let actual = machineInfo(outcome.machine).value
  assert uint64(actual.pc) == (if exit == 0: 6'u64 else: 0'u64)
  assert uint64(actual.gas) == 0 and actual.blockCharged
  for index in 0..<13:
    # A0 alone can change; the source CPU and every unrelated register remain intact.
    assert uint64(actual.registers[index]) == (if index == 7: expectedA0 else: uint64(regs[index]))
    assert uint64(machineInfo(source).value.registers[index]) == uint64(regs[index])
  let posterior = pageImage(memoryOf(outcome.machine).value, PageIndex(0xfffff)).value
  assert posterior.access == access
  for index in 0..<4096:
    # The two recorded bytes cover both candidate stores; all other bytes stay sentinel7.
    let wanted = if mapping == 0: 7'u8
      elif index == 4094: byte(data[at + 23])
      elif index == 4095: byte(data[at + 24]) else: 7'u8
    assert posterior.bytes[index] == wanted
  assert pageImage(memoryOf(source).value, PageIndex(0xfffff)).value.bytes == image.bytes
  assert pageImage(memory, PageIndex(0xfffff)).value.bytes == image.bytes

echo "PVM executed memory boundary reference passed: 12"
