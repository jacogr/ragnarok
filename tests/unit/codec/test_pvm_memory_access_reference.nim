# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay independent scalar memory equations, permission edges and original-register aliases.

import std/assertions
import std/syncio
import std/envvars
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/gas_plan as pvm_gas_plan
import ../../../src/pvm/gas_memo as pvm_gas_memo
import ../../../src/pvm/step as pvm_step

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed little-endian test fields only after their enclosing extent is validated.
  result = 0
  for i in 0..<width:
    # Never share the production program decoder with fixture expectation framing.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc originalByte(index, seed: int): byte =
  ## Unequal byte positions expose little-endian, signedness and accidental neighboring writes.
  byte(((index * 37 + seed) xor (index shr 4)) and 255)

proc verifySnapshot(source: Machine, data: string, at: int, pc, gas: uint64,
    charged, original: bool, access: array[2, PageAccess]) =
  ## Compare every CPU field and physical byte against the frozen row; original snapshots use the independently authored input registers/bytes.
  let cpu = machineInfo(source).value
  assert uint64(cpu.pc) == pc and uint64(cpu.gas) == gas
  assert uint64(cpu.gasDeficit) == 0 and cpu.blockCharged == charged
  let base = if original: 26 else: 130
  for i in 0..<13:
    assert uint64(cpu.registers[i]) == word(data, at+base+i*8,
        8) # All untouched registers are part of the witness.
  let address = word(data, at+9, 4)
  let writes = if original: 0 else: int(byte(data[at+17]))
  let seed = int(byte(data[at+16]))
  for page in 0..<2:
    # Permission changes are independently selected by the repair caller, never inferred from the returned memory.
    let observed = pageImage(memoryOf(source).value, PageIndex(uint32(16+page))).value
    assert observed.access == access[page]
    for i in 0..<4096:
      let absolute = 0x10000'u64+uint64(page*4096+i)
      let expected = if absolute >= address and absolute-address < uint64(writes):
        byte(data[at+18+int(absolute-address)])
        else: originalByte(page*4096+i, seed)
      assert observed.bytes[i] == expected # Include every untouched prefix/suffix and hidden inaccessible byte.

func mapping(access: PageAccess): int =
  ## Translate permissions into the frozen corpus's independent wire mapping, whose RO/RW ordinals differ from the native enum.
  if access == PageAccess.Inaccessible: 0
  elif access == PageAccess.ReadWrite: 1
  else: 2

proc run(source: Machine, mode: int, plan: GasPlan, memo: GasMemo): StepResult =
  ## Reuse the actual invocation overloads; modes two/three are cold/warm queries through the same memo identity.
  case mode
  of 0: execute(source, ExecutionStepLimit(2), GasCycleLimit(28))
  of 1: execute(source, ExecutionStepLimit(2), plan)
  else: execute(source, ExecutionStepLimit(2), memo)

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
  let accesses = [images[0].access, images[1].access]
  verifySnapshot(outcome.machine, data, at, (if exit == 0: uint64(wire[2])-1 else: 0'u64),
    0, true, false, accesses)
  verifySnapshot(source, data, at, 0, 0, true, true, accesses)
  # The frozen all-writable row has identical guest/register inputs and independently computed successful bytes/registers.
  let successfulAt = at-(row mod 27)*(234+int(length))+(12+row mod 3)*(234+int(length))
  assert successfulAt >= 12 and successfulAt+234+int(length) <= data.len
  assert word(data, successfulAt, 4) == length and byte(data[successfulAt+4]) == 0
  for i in 0..<int(length):
    assert byte(data[successfulAt+234+i]) == wire[
        i] # Do not pair a repaired result with another variant's expected state.
  for i in 0..<13:
    assert word(data, successfulAt+26+i*8, 8) == uint64(registers[i])
  let prepared = newGasPlan(decoded.value, GasPlanLimits(blocks: GasPlanBlockLimit(1),
    bytes: GasPlanByteLimit(256), cycles: GasCycleLimit(28)))
  assert prepared.error == GasPlanError.None
  assert uint64(blockGas(prepared.value, CodeAddress(0)).value) == 25
  for prepaid in [false, true]:
    # The independent pipeline model prices each exact scalar-plus-trap block at25 gas and28 cycles, including aliases.
    let cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(if prepaid: 7'u64 else: 32'u64),
      gasDeficit: GasDeficit(0), blockCharged: prepaid, registers: registers)
    let original = captureMachine(decoded.value, memory, cpu).value
    let learned = newGasMemo(decoded.value, GasMemoLimits(bytes: GasMemoByteLimit(256),
        cycles: GasCycleLimit(28)))
    assert learned.error == GasMemoError.None
    for mode in 0..<4:
      # Full execution includes the real trailing trap; successful calls normalize its terminal PC while faults retain their causing PC.
      let evaluated = run(original, mode, prepared.value, learned.value)
      assert evaluated.error == StepError.None
      var current = evaluated.value
      assert current.exit == (if exit == 0: StepExit.Panic else: StepExit.Fault)
      if exit == 2: assert uint64(uint32(current.faultPage)) == expectedFault
      verifySnapshot(current.machine, data, at, 0, 7, true, false, accesses)
      verifySnapshot(original, data, at, 0, uint64(cpu.gas), prepaid, true, accesses)
      var repairedAccess = accesses
      var retained: seq[StepOutcome] = @[]
      var retainedAccess: seq[array[2, PageAccess]] = @[]
      var repairs = 0
      while current.exit == StepExit.Fault:
        # Repair exactly the reported page; a missing high page may expose the original read-only low-page fault next.
        assert repairs < 2
        retained.add(current)
        retainedAccess.add(repairedAccess)
        let page = int(uint32(current.faultPage) div 4096)-16
        assert page >= 0 and page < 2 and repairedAccess[page] != PageAccess.ReadWrite
        var image = images[page]
        image.access = PageAccess.ReadWrite
        repairedAccess[page] = PageAccess.ReadWrite
        let patched = withPage(memoryOf(current.machine).value, image)
        assert patched.error == MachineError.None
        let resumed = withMemory(current.machine, patched.value)
        assert resumed.error == MachineError.None
        let retried = run(resumed.value, mode, prepared.value, learned.value)
        assert retried.error == StepError.None
        current = retried.value
        inc repairs
        let repairedAt = at-(row mod 27)*(234+int(length)) +
          ((mapping(repairedAccess[0])*3+mapping(repairedAccess[1]))*3+row mod 3)*(234+int(length))
        assert repairedAt >= 12 and repairedAt+234+int(length) <= data.len
        let repairFault = byte(data[repairedAt+4]) == 2
        assert current.exit == (if repairFault: StepExit.Fault else: StepExit.Panic)
        if repairFault:
          var expectedPage = word(data, repairedAt+5, 4)
          if storing and address < 0x11000 and address+uint64(width) > 0x11000 and
              repairedAccess[0] == PageAccess.ReadOnly and repairedAccess[1] ==
                  PageAccess.Inaccessible:
            expectedPage = 0x11000 # Keep only the documented GP-PVM-008 adapter over the selected frozen row.
          assert uint64(uint32(current.faultPage)) == expectedPage
        verifySnapshot(current.machine, data, repairedAt, 0, 7, true, false, repairedAccess)
      for i in 0..<retained.len:
        verifySnapshot(retained[i].machine, data, at, 0, 7, true, true, retainedAccess[
            i]) # Later repairs/writes cannot mutate any earlier frozen fault.
      verifySnapshot(original, data, at, 0, uint64(cpu.gas), prepaid, true, accesses)
      assert gasMemoInfo(learned.value).value.pricedBlocks == (if prepaid or mode <
          2: 0'u64 else: 1'u64)
      if not prepaid:
        var poor = cpu
        poor.gas = MachineGas(24)
        let waiting = captureMachine(decoded.value, memory, poor).value
        let refused = run(waiting, mode, prepared.value, learned.value)
        assert refused.error == StepError.None and refused.value.exit == StepExit.OutOfGas
        verifySnapshot(refused.value.machine, data, at, 0, 24, false, true, accesses)
        verifySnapshot(waiting, data, at, 0, 24, false, true, accesses)
    let strict = newGasMemo(decoded.value, GasMemoLimits(bytes: GasMemoByteLimit(256),
        cycles: GasCycleLimit(27)))
    assert strict.error == GasMemoError.None
    for repeat in 0..<2:
      # A distinct one-less policy cannot inherit the successful28-cycle fact, even after a previous failed query.
      let limited = execute(original, ExecutionStepLimit(2), strict.value)
      let dynamic = execute(original, ExecutionStepLimit(2), GasCycleLimit(27))
      if prepaid:
        for completed in [limited, dynamic]:
          assert completed.error == StepError.None and completed.value.exit == (if exit ==
              0: StepExit.Panic else: StepExit.Fault)
          verifySnapshot(completed.value.machine, data, at, 0, 7, true, false, accesses)
      else:
        assert limited.error == StepError.GasCycleLimitExceeded and dynamic.error ==
            StepError.GasCycleLimitExceeded
      assert gasMemoInfo(strict.value).value.pricedBlocks == 0
      verifySnapshot(original, data, at, 0, uint64(cpu.gas), prepaid, true, accesses)
  let strictPlan = newGasPlan(decoded.value, GasPlanLimits(blocks: GasPlanBlockLimit(1),
    bytes: GasPlanByteLimit(256), cycles: GasCycleLimit(27)))
  assert strictPlan.error == GasPlanError.CycleLimitExceeded
assert cursor == data.len and compatibilityCases == 48

echo "PVM scalar memory access reference passed: 4050; full pricing and paid repairs"
