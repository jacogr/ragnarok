# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Measure only execution of independently specified PVM workloads; validate outside the timed region.

import std/[assertions, syncio, envvars, monotimes]
import ../../src/pvm/[program, machine, gas, step]

type HostContext = object ## Plain host progress is included in both embeddings' execution time.
  calls: uint64

proc word(data: string, at, width: int): uint64 =
  ## Read fixed fields after their enclosing record extent is validated.
  result = 0
  for i in 0..<width:
    # Framing is independent of the production operand decoder.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Test host replies perform the same increment/sum as the Rust benchmark embedding.
  let cpu = machineInfo(suspension.machine).value
  var registers = cpu.registers
  if uint64(suspension.hostCall) == 13:
    # Host dispatch and reply construction are part of the measured embedding workload.
    registers[7] = RegisterValue(uint64(registers[7]) + 1)
  else:
    # Unexpected host identifiers are failures, never accepted timing samples.
    assert uint64(suspension.hostCall) == 14
    registers[8] = RegisterValue(uint64(registers[8]) + uint64(registers[7]))
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: memoryOf(suspension.machine).value)

var data = ""
try:
  # Missing input is a setup error and must never yield an empty timing result.
  data = readFile(getEnv("RAGNAROK_PVM_BENCHMARK"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMBEN01" and word(data, 8, 4) == 10
var cursor = 12
for row in 0..<10:
  # Bound guest inputs before timing or narrowing; malformed corpora cannot create measurements.
  assert data.len - cursor >= 273
  let at = cursor
  let length = word(data, at, 4)
  let kind = byte(data[at + 4])
  let iterations = word(data, at + 5, 4)
  let address = word(data, at + 9, 4)
  let initial = word(data, at + 13, 8)
  let price = word(data, at + 29, 8)
  let cycles = word(data, at + 37, 8)
  let halt = word(data, at + 45, 4)
  let haltPrice = word(data, at + 49, 8)
  assert kind <= 4 and iterations > 0 and iterations <= 10000
  assert price > 0 and price < 1000 and haltPrice > 0 and haltPrice < 1000
  assert cycles > 0 and cycles < 1000
  cursor += 273
  assert length >= 4 and length <= 128 and length <= uint64(data.len - cursor)
  let preparation = getMonoTime().ticks
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Captured program bytes and memory are prepared once, outside all execution samples.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value
  var images: seq[PageImage] = @[]
  if kind in [1'u8, 2, 4]:
    # Aligned/crossing guests touch the same first pair; sparse cases retain additional mapped canaries.
    assert address in [0x10000'u64, 0x10fff'u64]
    # Sparse cases admit 64 two-page pairs separated by unmapped holes; all retained bytes validate.
    for page in 0..<(if kind == 4: 128 else: 2):
      var image = PageImage(index: PageIndex(uint32(16 + (if kind == 4: (page div 2)*4 +
          page mod 2 else: page))), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
      for i in 0..<4096: image.bytes[i] = 33
      images.add(image)
    for i in 0..<8:
      # Initial scalar bytes are copied from the independent fixture before execution begins.
      let offset = int(address - 0x10000) + i
      images[offset div 4096].bytes[offset mod 4096] = byte((initial shr (8 * i)) and 255)
  let memory = captureMemory(images, PageLimit(if kind == 4: 128 else: 2)).value
  var registers = default(RegisterFile)
  for i in 0..<13: registers[i] = RegisterValue(word(data, at + 65 + i * 8, 8))
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(iterations * price + haltPrice + 7), blockCharged: false,
        registers: registers)).value
  let prepareNs = getMonoTime().ticks - preparation
  assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(cycles)).value) == price
  assert uint64(blockGas(program, CodeAddress(halt), GasCycleLimit(cycles)).value) == haltPrice
  let perLoop = if kind == 0: 3'u64 elif kind in [1'u8, 4]: 5'u64 elif kind == 3: 9'u64 else: 6'u64
  for sample in 0..<13:
    # Three warmups precede ten recorded samples; source owners are immutable across every run.
    var context = HostContext(calls: 0)
    let start = getMonoTime().ticks
    let evaluated = if kind == 2:
      executeWithHost(source, context, respond, ExecutionStepLimit(perLoop * iterations + 1),
        HostCallLimit(2 * iterations), GasCycleLimit(cycles))
      else: execute(source, ExecutionStepLimit(perLoop * iterations + 1), GasCycleLimit(cycles))
    let elapsed = getMonoTime().ticks - start
    # Complete result validation happens after the clock stops; failed outcomes never emit a sample.
    assert evaluated.error == StepError.None and evaluated.value.exit == StepExit.Halt
    let final = machineInfo(evaluated.value.machine).value
    assert uint64(final.gas) == 7 and uint64(final.pc) == 0 and final.blockCharged
    assert context.calls == (if kind == 2: 2 * iterations else: 0'u64)
    for i in 0..<13:
      assert uint64(final.registers[i]) == word(data, at + 169 + i * 8, 8)
      assert uint64(machineInfo(source).value.registers[i]) == uint64(registers[i])
    for page in 0..<images.len:
      # Full byte checks retain output observability and catch extra writes beyond the measured scalar.
      let actual = pageImage(memoryOf(evaluated.value.machine).value, PageIndex(uint32(16 + (
          if kind == 4: (page div 2)*4 + page mod 2 else: page)))).value
      assert actual.access == PageAccess.ReadWrite
      for i in 0..<4096:
        let physical = 0x10000'u64 + uint64((int(uint32(images[page].index))-16) * 4096 + i)
        let expected = if physical >= address and physical - address < 8:
          byte((word(data, at + 21, 8) shr (8 * int(physical - address))) and 255) else: 33'u8
        assert actual.bytes[i] == expected
      assert pageImage(memoryOf(source).value, PageIndex(uint32(16 + (if kind == 4: (page div 2)*4 +
          page mod 2 else: page)))).value.bytes == images[page].bytes
    if kind == 4:
      for pair in 0..<64:
        # Unmapped holes remain faults in both the retained source and final immutable result.
        let hole = MemoryAddress(uint64(0x12000 + pair*16384))
        assert load(memoryOf(source).value, hole, AccessWidth(1)).error == MachineError.Fault
        assert load(memoryOf(evaluated.value.machine).value, hole, AccessWidth(1)).error ==
            MachineError.Fault
    assert elapsed > 0
    echo "sample\t", row, "\t", sample, "\t", elapsed, "\t", prepareNs
assert cursor == data.len
