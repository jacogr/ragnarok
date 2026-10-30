# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two-stage cross-page environment repair preserves prepaid gas, atomic stores and old owners.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed test fields only after the enclosing record extent is validated.
  result = 0
  for i in 0..<width:
    # Fixture framing remains independent of the production operand decoder.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc sameMemory(memory: Memory, images: openArray[PageImage]) =
  ## Compare complete copied bytes and permissions, including retained inaccessible images.
  for image in images:
    # Immutable source aliases must retain all bytes after both failed and successful retries.
    let actual = pageImage(memory, image.index).value
    assert actual.access == image.access and actual.bytes == image.bytes

proc sameCpu(machine: Machine, registers: RegisterFile, gas: uint64, charged: bool, pc: uint64) =
  ## Compare all CPU fields at each gas/fault/repair boundary.
  let actual = machineInfo(machine).value
  assert uint64(actual.pc) == pc and uint64(actual.gas) == gas and actual.blockCharged == charged
  for i in 0..<13:
    # A store never mutates its base/value registers, including aliases.
    assert uint64(actual.registers[i]) == uint64(registers[i])

var data = ""
try:
  # Missing frozen inputs fail setup; no native test regenerates paper expectations.
  data = readFile(getEnv("RAGNAROK_PVM_CROSS_PAGE_RETRY"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMCRY01" and word(data, 8, 4) == 48
var cursor = 12
for row in 0..<48:
  # Record sizes, physical addresses and scalar widths are proved before conversion or indexing.
  assert data.len - cursor >= 250
  let at = cursor
  let length = word(data, at, 4)
  let address = word(data, at + 9, 4)
  let width = int(byte(data[at + 13]))
  let seed = int(byte(data[at + 16]))
  assert width in [2, 4, 8] and address < 0x11000 and address + uint64(width) > 0x11000
  assert word(data, at + 5, 4) == 0x10000
  assert byte(data[at + 14]) == 2 and byte(data[at + 15]) == 0
  assert int(byte(data[at + 17])) == width
  assert word(data, at + 234, 8) == 25 and word(data, at + 242, 8) == 28
  cursor += 250
  assert length >= 4 and length <= 32 and length <= uint64(data.len - cursor)
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Preserve the same original raw program bytes as the public reference.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
  assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(28)).value) == 25
  assert blockGas(program, CodeAddress(0), GasCycleLimit(27)).error == GasError.CycleLimitExceeded
  var registers = default(RegisterFile)
  for i in 0..<13:
    # Successful stores and both faults preserve the independently frozen full register file.
    registers[i] = RegisterValue(word(data, at + 26 + i * 8, 8))
    assert uint64(registers[i]) == word(data, at + 130 + i * 8, 8)
  var original = default(array[2, PageImage])
  for page in 0..<2:
    # Lower read-only and higher absent images own sentinel bytes before any repair.
    original[page] = PageImage(index: PageIndex(uint32(16 + page)),
      access: (if page == 0: PageAccess.ReadOnly else: PageAccess.Inaccessible),
      bytes: default(array[4096, byte]))
    for i in 0..<4096:
      # One continuous unequal pattern exposes partial writes and wrong cross-page byte placement.
      let index = page * 4096 + i
      original[page].bytes[i] = byte(((index * 37 + seed) xor (index shr 4)) and 255)
  let memory = captureMemory(original, PageLimit(2)).value
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(24), blockCharged: false, registers: registers)).value
  let underfunded = stepMemory(source, GasCycleLimit(28)).value
  assert underfunded.exit == StepExit.OutOfGas
  sameCpu(underfunded.machine, registers, 24, false, 0)
  sameMemory(memoryOf(underfunded.machine).value, original)
  for budget in [25'u64, 32'u64]:
    # A fresh funded snapshot proves exact gas zero can complete the prepaid block after both repairs.
    let funded = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(budget), blockCharged: false, registers: registers)).value
    let first = stepMemory(funded, GasCycleLimit(28)).value
    assert first.exit == StepExit.Fault and uint32(first.faultPage) == 0x11000
    sameCpu(first.machine, registers, budget - 25, true, 0)
    sameMemory(memoryOf(first.machine).value, original)
    var higher = original
    higher[1].access = PageAccess.ReadWrite
    let mapped = withPage(memoryOf(first.machine).value, higher[1]).value
    let repairedHigher = withMemory(first.machine, mapped).value
    let second = stepMemory(repairedHigher, GasCycleLimit(0)).value
    assert second.exit == StepExit.Fault and uint32(second.faultPage) == 0x10000
    sameCpu(second.machine, registers, budget - 25, true, 0)
    sameMemory(memoryOf(second.machine).value, higher)
    var writable = higher
    writable[0].access = PageAccess.ReadWrite
    let unprotected = withPage(memoryOf(second.machine).value, writable[0]).value
    let repairedLower = withMemory(second.machine, unprotected).value
    let stored = stepMemory(repairedLower, GasCycleLimit(0)).value
    assert stored.exit == StepExit.Continued
    sameCpu(stored.machine, registers, budget - 25, true, uint64(wire[2]) - 1)
    var expected = writable
    for i in 0..<width:
      # Only final success publishes the paper-derived low stored bytes across the two owned pages.
      let offset = int(address - 0x10000) + i
      expected[offset div 4096].bytes[offset mod 4096] = byte(data[at + 18 + i])
    sameMemory(memoryOf(stored.machine).value, expected)
    let completed = execute(repairedLower, ExecutionStepLimit(2), GasCycleLimit(0)).value
    assert completed.exit == StepExit.Panic
    sameCpu(completed.machine, registers, budget - 25, true, 0)
    sameMemory(memoryOf(completed.machine).value, expected)
    sameMemory(memoryOf(repairedLower).value, writable)
    sameMemory(memoryOf(second.machine).value, higher)
    sameMemory(memoryOf(first.machine).value, original)
    sameMemory(memoryOf(funded).value, original)
    sameCpu(funded, registers, budget, false, 0)
  sameCpu(source, registers, 24, false, 0)
  sameMemory(memory, original)
assert cursor == data.len

echo "PVM metered cross-page repair passed: 48 rows, 96 budget/repair sequences"
