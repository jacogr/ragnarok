# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full 139-opcode, alias, gas and exit matrix across direct and public snapshot execution boundaries.

import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Fixed four-byte table entries are independent of operand decoding and may deliberately name invalid code targets.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None
  decoded.value

proc sameCpu(left, right: MachineInfo) =
  ## All copied CPU fields participate, including the prepaid-block state and reserved gas deficit.
  assert uint64(left.pc) == uint64(right.pc)
  assert uint64(left.gas) == uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit)
  assert left.blockCharged == right.blockCharged
  for index in 0..<13:
    # Compare every register, including operands intentionally aliased by a witness.
    assert uint64(left.registers[index]) == uint64(right.registers[index])

proc memory(): Memory =
  ## Distinct nonzero bytes expose clobbering and partial cross-page writes.
  var pages = default(array[2, PageImage])
  for index in 0..<2:
    pages[index] = PageImage(index: PageIndex(uint32(16+index)),
        access: PageAccess.ReadWrite)
    for at in 0..<4096:
      pages[index].bytes[at] = byte((at*17+index*31+3) mod 256)
  captureMemory(pages, PageLimit(2)).value

proc cache(source: Program): FlatPlan =
  ## Program facts and prices are sealed once; executable stream and input memory remain frame-local.
  newFlatPlan(source, GasCycleLimit(100000))

proc same(actual: FlatFrame, expected: StepResult, sourcePages: openArray[PageImage]) =
  ## Failed local runs expose no successful comparison state; every genuine exit checks all selected metadata and mapped bytes.
  assert actual.reason == expected.error
  if expected.error == StepError.None:
    let wanted = expected.value
    assert actual.exit == wanted.exit
    if wanted.exit == StepExit.Fault: assert uint32(actual.faultPage) == uint32(wanted.faultPage)
    if wanted.exit == StepExit.Host: assert uint64(actual.hostCall) == uint64(wanted.hostCall)
    sameCpu(actual.info, machineInfo(wanted.machine).value)
    let memory = flatMemorySnapshot(actual)
    for page in [16'u32, 17'u32]:
      let a = pageImage(memory, PageIndex(page))
      let b = pageImage(memoryOf(wanted.machine).value, PageIndex(page))
      assert a.error == b.error
      if a.error == MachineError.None:
        let ai = a.value
        let bi = b.value
        assert ai.access == bi.access and ai.bytes == bi.bytes
  checkFlatSource(actual, sourcePages)

proc compare(input: Machine, prepared: FlatPlan, steps, cycles: uint64) =
  ## A fresh and reused handler stream see the same original registers and private input reset on each call.
  let info = machineInfo(input).value
  let mem = memoryOf(input).value
  let pages = [pageImage(mem, PageIndex(16)).value, pageImage(mem, PageIndex(17)).value]
  let expected = execute(input, ExecutionStepLimit(steps), GasCycleLimit(cycles))
  var frame = newFlatFrame(prepared, pages, info)
  for repeat in 0..<2:
    resetFlatFrame(frame, info)
    runFlat(frame, steps)
    same(frame, expected, pages)
    sameCpu(machineInfo(input).value, info)

let mapped = memory()
var registers = default(RegisterFile)
for index in 0..<13: registers[index] = RegisterValue(0xabcdef01'u64+uint64(index)*31)

proc immediate(bytes: var seq[byte], value: uint64) =
  for shift in 0..<4: bytes.add(byte((value shr (shift*8)) and 255))

proc firstMemoryPart(code: byte, address: uint64): seq[byte] =
  ## Encode actual mapped absolute/indirect operands independently of the production decoder, with a deliberately aliased register1.
  result = @[code]
  if code <= 33:
    # Absolute immediate stores carry two explicitly four-byte immediates.
    result.add(4)
    immediate(result, address)
    immediate(result, 0x89abcdef'u64)
  elif code in {70'u8..73'u8}:
    # Indirect immediate stores select base1 and a four-byte offset followed by four-byte data.
    result.add(65)
    immediate(result, 0)
    immediate(result, 0x89abcdef'u64)
  else:
    # Absolute forms select A1; indirect register forms alias source/destination/base1.
    result.add(if code < 120: 1'u8 else: 17'u8)
    immediate(result, if code < 120: address else: 0'u64)

proc memoryPrefixMatrix(initialRegisters: RegisterFile) =
  ## Every checked memory-first family precedes every genuine second opcode under success, permission and cross-page faults.
  let memoryCodes = [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
    70, 71, 72, 73, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130]
  for firstCode in memoryCodes:
    for secondCode in 0..255:
      if validOpcode(byte(secondCode)):
        # Saturated repeated descriptors expose first-load register aliasing before the second instruction reads its inputs.
        var second = @[byte(secondCode)]
        for index in 0..<24: second.add(17'u8)
        for address in [65536'u64, 69631, 73727]:
          let program = owner([firstMemoryPart(firstCode, address), second, @[0'u8]])
          let prepared = cache(program)
          for access in [PageAccess.ReadWrite, PageAccess.ReadOnly]:
            # A fresh owner changes permissions without changing any retained code fact or scalar memory window.
            var images = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
            images[1].access = access
            let memory = captureMemory(images, PageLimit(2)).value
            var initial = initialRegisters
            initial[1] = RegisterValue(address)
            let source = captureMachine(program, memory, MachineInfo(gas: MachineGas(100000),
              blockCharged: true, registers: initial)).value
            for steps in [0'u64, 1, 2, 3]:
              # Early first exits must publish their own source PC; one attempt must never execute a genuine second operation.
              compare(source, prepared, steps, 100000)

memoryPrefixMatrix(registers)

echo "PASS 25020 memory-first pairs / budgets 0..3 / alias+permission+cross-page / fresh+reused"

proc addMemoryMatrix(initialRegisters: RegisterFile) =
  ## Compare add/memory chains with individual Psi_1 calls, which never select combined workers.
  ## Aliased address/value/destination1 must observe the completed add, including on second-node
  ## permission or cross-page faults. Full and partial budgets preserve the original source boundary.
  let memoryCodes = [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
    70, 71, 72, 73, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130]
  for first in [149'u8, 200'u8]:
    for second in memoryCodes:
      for address in [65536'u64, 69631, 73727]:
        # Both independently encoded adds write register1 from the same original address-7 and7.
        let prefix = if first == 149: @[149'u8, 17, 7, 0, 0, 0] else: @[200'u8, 33, 1]
        let memoryPart = firstMemoryPart(second, address)
        let program = owner([prefix, memoryPart, @[0'u8]])
        let prepared = cache(program)
        for access in [PageAccess.ReadWrite, PageAccess.ReadOnly]:
          # A writable first page and a possibly protected second page expose atomic scalar preflight.
          var pages = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
          pages[1].access = access
          let memory = captureMemory(pages, PageLimit(2)).value
          for gas in [0'u64, 1, 100000]:
            var initial = initialRegisters
            initial[1] = RegisterValue(address-7)
            initial[2] = RegisterValue(7)
            let info = MachineInfo(gas: MachineGas(gas), registers: initial)
            let input = captureMachine(program, memory, info).value
            for steps in 0..3:
              var wanted = input
              var kind = StepExit.Continued
              var fault = PageAddress(0)
              for attempt in 0..<steps:
                # Each reference call has single-instruction admission, preventing add/memory fusion.
                let one = stepOnce(wanted, GasCycleLimit(100000))
                assert one.error == StepError.None
                let outcome = one.value
                wanted = outcome.machine
                kind = outcome.exit
                if kind == StepExit.Fault: fault = outcome.faultPage
                if attempt == 0 and kind == StepExit.Continued:
                  assert uint64(machineInfo(wanted).value.registers[1]) == address
                if kind != StepExit.Continued: break
              var frame = newFlatFrame(prepared, pages, info)
              for repeat in 0..<2:
                # Reused emitted code must reset private bytes and keep the independently stepped result.
                resetFlatFrame(frame, info)
                runFlat(frame, uint64(steps))
                if kind == StepExit.Continued:
                  assert frame.reason == StepError.StepLimitExceeded
                else:
                  assert frame.reason == StepError.None and frame.exit == kind
                  if kind == StepExit.Fault: assert uint32(frame.faultPage) == uint32(fault)
                var expectedInfo = machineInfo(wanted).value
                if kind == StepExit.Panic:
                  # Psi_1 advances past trap; recursive execution normalizes terminal PC to zero.
                  assert uint64(expectedInfo.pc) == uint64(prefix.len+memoryPart.len+1)
                  expectedInfo.pc = CodeAddress(0)
                sameCpu(frame.info, expectedInfo)
                let actual = flatMemorySnapshot(frame)
                let expected = memoryOf(wanted).value
                for page in [16'u32, 17'u32]:
                  # Check complete permission/byte images, including every untouched lane of a refused store.
                  let left = pageImage(actual, PageIndex(page)).value
                  let right = pageImage(expected, PageIndex(page)).value
                  assert left.access == right.access and left.bytes == right.bytes
                checkFlatSource(frame, pages)

addMemoryMatrix(registers)
echo "PASS add-memory pairs / individual-step oracle / gas+quota+alias+permission+cross-page / fresh+reused"
