# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay independent scalar memory equations, permission edges and original-register aliases.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, step]

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed little-endian test fields only after their enclosing extent is validated.
  result = 0
  for i in 0..<width:
    # Never share the production program decoder with fixture expectation framing.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc originalByte(index, seed: int): byte =
  ## Unequal byte positions expose little-endian, signedness and accidental neighboring writes.
  byte(((index * 37 + seed) xor (index shr 4)) and 255)

var data = ""
try:
  # A missing frozen corpus is a setup failure; ordinary native execution never regenerates it.
  data = readFile(getEnv("RAGNAROK_PVM_MEMORY_ACCESS"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMMAC01"
assert word(data, 8, 4) == 4050
var cursor = 12
var compatibilityCases = 0
for row in 0..<4050:
  # Check all untrusted header fields and remaining blob bytes before access or narrowing.
  assert data.len - cursor >= 234
  let at = cursor
  let length = word(data, at, 4)
  let exit = byte(data[at + 4])
  let fault = word(data, at + 5, 4)
  let address = word(data, at + 9, 4)
  let width = int(byte(data[at + 13]))
  let seed = int(byte(data[at + 16]))
  let writes = int(byte(data[at + 17]))
  assert exit in {0'u8, 2} and width in [1, 2, 4, 8]
  assert address >= 0x10000 and address + uint64(width) <= 0x12000
  assert writes == 0 or writes == width
  cursor += 234
  assert length >= 4 and length <= 32 and length <= uint64(data.len - cursor)
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Copy the literal independently encoded guest bytes into an immutable captured program owner.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  # Keep the frozen paper fault unchanged; apply only the documented GP-PVM-008 adapter.
  let op = wire[3]
  let storing = op in {30'u8..33'u8, 59'u8..62'u8, 70'u8..73'u8, 120'u8..123'u8}
  var expectedFault = fault
  if storing and address < 0x11000 and address + uint64(width) > 0x11000 and
      byte(data[at + 14]) == 2 and byte(data[at + 15]) == 0:
    assert fault == 0x10000
    expectedFault = 0x11000
    inc compatibilityCases
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  var images = default(array[2, PageImage])
  for page in 0..<2:
    # Retain sentinel bytes even for inaccessible pages to detect accidental owned-state mutation.
    let mapping = byte(data[at + 14 + page])
    assert mapping <= 2
    let access = if mapping == 0: PageAccess.Inaccessible
      elif mapping == 1: PageAccess.ReadWrite else: PageAccess.ReadOnly
    images[page] = PageImage(index: PageIndex(uint32(16 + page)), access: access,
      bytes: default(array[4096, byte]))
    for i in 0..<4096:
      # Both pages use one continuous unequal byte pattern across the boundary.
      images[page].bytes[i] = originalByte(page * 4096 + i, seed)
  let captured = captureMemory(images, PageLimit(2))
  assert captured.error == MachineError.None
  let memory = captured.value
  var registers = default(RegisterFile)
  for i in 0..<13:
    # Full-width source registers preserve high base bits and A/B alias witnesses.
    registers[i] = RegisterValue(word(data, at + 26 + i * 8, 8))
  let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: true,
    registers: registers)
  let source = captureMachine(decoded.value, memory, info).value
  let stepped = stepMemory(source, GasCycleLimit(0))
  assert stepped.error == StepError.None
  let outcome = stepped.value
  assert outcome.exit == (if exit == 0: StepExit.Continued else: StepExit.Fault)
  if exit == 2:
    # The scoped compatibility rule selects absent mappings before read-only write faults.
    assert uint64(uint32(outcome.faultPage)) == expectedFault
  else:
    # The public interpreter reaches this following trap; native stepping stops just before it.
    assert fault == 0
  let posterior = machineInfo(outcome.machine).value
  assert uint64(posterior.pc) == (if exit == 0: uint64(wire[2]) - 1 else: 0'u64)
  assert uint64(posterior.gas) == 0 and posterior.blockCharged
  for i in 0..<13:
    # Independent complete register expectations include successful signed loads and failure preservation.
    assert uint64(posterior.registers[i]) == word(data, at + 130 + i * 8, 8)
    assert uint64(machineInfo(source).value.registers[i]) == uint64(registers[i])
  for page in 0..<2:
    # Check every owned byte, including untouched prefixes of failed cross-page stores and source aliases.
    let observed = pageImage(memoryOf(outcome.machine).value, PageIndex(uint32(16 + page))).value
    let original = pageImage(memoryOf(source).value, PageIndex(uint32(16 + page))).value
    assert observed.access == images[page].access and original.access == images[page].access
    for i in 0..<4096:
      # Expected writes are fixture values; no native memory operation computes its own expected result.
      let absolute = 0x10000'u64 + uint64(page * 4096 + i)
      let expected = if absolute >= address and absolute - address < uint64(writes):
        byte(data[at + 18 + int(absolute - address)])
        else: originalByte(page * 4096 + i, seed)
      assert observed.bytes[i] == expected
      assert original.bytes[i] == images[page].bytes[i]
    assert pageImage(memory, PageIndex(uint32(16 + page))).value.bytes == images[page].bytes
assert cursor == data.len and compatibilityCases == 48

echo "PVM scalar memory access reference passed: 4050"
