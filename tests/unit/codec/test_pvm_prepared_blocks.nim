# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Differential prepared execution covers the complete opcode set, source snapshots, budgets, cache reuse and bounded segments.
# @@Verification={"arc": "pvm_prepared_blocks_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, gas, step]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]]): Program =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes = @[0'u8, 0]
  appendNatural(bytes, uint64(code.len))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc cache(program: Program, cycles: uint64 = 100000, bytes: uint64 = 1048576,
    blocks: uint32 = 128): PreparedProgram =
  ## Tests choose explicit bounded policies; creation must not prepare any instruction or block price.
  let created = newPreparedProgram(program, PreparedLimits(
      bytes: PreparedByteLimit(bytes),
    blocks: PreparedBlockLimit(blocks), cycles: GasCycleLimit(cycles)))
  assert created.error == PreparationError.None
  assert preparedInfo(created.value).value.preparedOperations == 0
  created.value

proc sameCpu(left, right: MachineInfo) =
  ## All copied CPU fields participate, including the prepaid-block state and reserved gas deficit.
  assert uint64(left.pc) == uint64(right.pc)
  assert uint64(left.gas) == uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit)
  assert left.blockCharged == right.blockCharged
  for index in 0..<13:
    # Compare every register, including operands intentionally aliased by a witness.
    assert uint64(left.registers[index]) == uint64(right.registers[index])

proc same(left, right: StepResult) =
  ## Local failures carry no selectable state; guest outcomes compare all state and exit metadata.
  assert left.error == right.error
  if left.error == StepError.None:
    let a = left.value
    let b = right.value
    assert a.exit == b.exit
    if a.exit == StepExit.Fault: assert uint32(a.faultPage) == uint32(b.faultPage)
    if a.exit == StepExit.Host: assert uint64(a.hostCall) == uint64(b.hostCall)
    sameCpu(machineInfo(a.machine).value, machineInfo(b.machine).value)
    for page in [16'u32, 17'u32]:
      # Both permissions and complete page bytes must survive faults, stores and exits identically.
      let first = pageImage(memoryOf(a.machine).value, PageIndex(page))
      let second = pageImage(memoryOf(b.machine).value, PageIndex(page))
      assert first.error == second.error
      if first.error == MachineError.None:
        assert first.value.access == second.value.access
        assert first.value.bytes == second.value.bytes

proc memory(): Memory =
  ## Distinct nonzero bytes expose clobbering and partial cross-page writes.
  var pages = default(array[2, PageImage])
  for index in 0..<2:
    pages[index] = PageImage(index: PageIndex(uint32(16+index)),
        access: PageAccess.ReadWrite)
    for at in 0..<4096:
      pages[index].bytes[at] = byte((at*17+index*31+3) mod 256)
  captureMemory(pages, PageLimit(2)).value

proc compare(input: Machine, prepared: PreparedProgram, steps: uint64,
    cycles: uint64) =
  ## Cold and reused execution compare against the unchanged interpreter, retaining the original source snapshot.
  let before = machineInfo(input).value
  let expected = execute(input, ExecutionStepLimit(steps), GasCycleLimit(cycles))
  for repeat in 0..<2:
    # Repeated calls share only prepared facts and always start from the same immutable machine.
    let actual = execute(input, ExecutionStepLimit(steps), prepared)
    same(actual, expected)
    sameCpu(machineInfo(input).value, before)
  let observed = preparedInfo(prepared).value
  assert observed.residentBytes <= uint64(observed.byteLimit)
  assert observed.residentBlocks <= uint64(uint32(observed.blockLimit))

let mapped = memory()
var registers = default(RegisterFile)
let patterns = [0'u64, high(uint64), 0x8000000000000000'u64, 0x80000000'u64,
  0x10000'u64, 0x10fff'u64, 0x11ffc'u64, 0xffff0000'u64, 63'u64, 32'u64, 1'u64,
      0x10001'u64, 0x12345678'u64]
for index in 0..<13: registers[index] = RegisterValue(patterns[index])
var opcodes = 0
for op in 0..255:
  # Each operand layout sees zeroed, saturated and mixed bit patterns; all code uses exact marked boundaries.
  if validOpcode(byte(op)):
    inc opcodes
    for pattern in [0'u8, 255'u8, 17'u8]:
      var part = @[byte(op)]
      for index in 0..<24: part.add(pattern)
      let program = owner([part, @[0'u8]])
      let prepared = cache(program)
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 512'u64]:
          # A paid source exercises instruction mutation independently of pipeline affordability.
          let source = captureMachine(program, mapped, MachineInfo(
              pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid,
                registers: registers)).value
          compare(source, prepared, 16, 100000)
assert opcodes == 139

# Long straight-line blocks cross the fixed preparation-segment capacity while paying one complete block price.
var longParts: seq[seq[byte]] = @[]
for index in 0..<700:
  # Load-immediate is a genuine nonterminator with an independently known final register value.
  longParts.add(@[51'u8, 7, byte(index mod 127)])
longParts.add(@[0'u8])
let longProgram = owner(longParts)
let longCache = cache(longProgram, blocks = 2)
let longPrice = uint64(blockGas(longProgram, CodeAddress(0), GasCycleLimit(100000)).value)
for gas in [longPrice-1, longPrice, longPrice+1, 1'u64 shl 63, high(uint64)]:
  let source = captureMachine(longProgram, mapped, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(gas), registers: registers)).value
  compare(source, longCache, 701, 100000)
assert preparedInfo(longCache).value.evictions > 0
assert preparedInfo(longCache).value.preparedOperations >= 701
# A tiny byte ceiling forces replacement even when the sparse slot index has unused entries.
let byteBounded = cache(longProgram, bytes = 2048, blocks = 128)
let byteSource = captureMachine(longProgram, mapped, MachineInfo(
    pc: CodeAddress(0),
  gas: MachineGas(longPrice), registers: registers)).value
compare(byteSource, byteBounded, 701, 100000)
assert preparedInfo(byteBounded).value.evictions > 0
assert preparedInfo(byteBounded).value.residentBlocks < 128
let longSource = captureMachine(longProgram, mapped, MachineInfo(
    pc: CodeAddress(0),
  gas: MachineGas(longPrice), registers: registers)).value
for steps in [0'u64, 1'u64, 255'u64, 256'u64, 257'u64, 700'u64]:
  # A local budget boundary cannot publish a prefix even when preparation already completed a segment.
  compare(longSource, longCache, steps, 100000)

# Program identity is exact: independently captured equal bytes cannot share prepared capabilities.
let first = owner([@[51'u8, 7, 11], @[0'u8]])
let second = owner([@[51'u8, 7, 11], @[0'u8]])
let firstCache = cache(first)
let wrongSource = captureMachine(second, mapped, MachineInfo(gas: MachineGas(100))).value
assert execute(wrongSource, ExecutionStepLimit(5), firstCache).error ==
    StepError.InvalidPreparedProgram
assert execute(wrongSource, ExecutionStepLimit(5), default(
    PreparedProgram)).error ==StepError.InvalidPreparedProgram
assert preparedInfo(default(PreparedProgram)).error ==
    PreparationError.InvalidProgram
assert newPreparedProgram(default(Program), PreparedLimits()).error ==
    PreparationError.InvalidProgram
assert newPreparedProgram(first, PreparedLimits(bytes: PreparedByteLimit(high(uint64)),
  blocks: PreparedBlockLimit(0))).error == PreparationError.LimitExceeded
assert newPreparedProgram(first, PreparedLimits(bytes: PreparedByteLimit(1),
  blocks: PreparedBlockLimit(1))).error == PreparationError.LimitExceeded
let firstSource = captureMachine(first, mapped, MachineInfo(gas: MachineGas(1000))).value
compare(firstSource, cache(first, cycles = 0), 5, 0)
let prepaid = captureMachine(first, mapped, MachineInfo(
    blockCharged: true)).value
compare(prepaid, cache(first, cycles = 0), 5, 0)
let paidInside = captureMachine(longProgram, mapped, MachineInfo(
    pc: CodeAddress(300), blockCharged: true)).value
compare(paidInside, longCache, 1000, 100000)
let unpaidInside = captureMachine(longProgram, mapped, MachineInfo(
    pc: CodeAddress(300), gas: MachineGas(longPrice))).value
compare(unpaidInside, longCache, 1000, 100000)

# Exact scalar operand formats exercise mapped, crossing, read-only and protected memory.
proc immediate(bytes: var seq[byte], value: uint64) =
  ## Fixed four-byte bit patterns are independent of the production operand decoder.
  for index in 0..<4: bytes.add(byte((value shr (8*index)) and 255))

for op in [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 70,
    71, 72, 73, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130]:
  # Every memory opcode selects its own prepared width/sign/address/source combination.
  for address in [0x10000'u64, 0x10fff'u64, 0x11ffc'u64, 0xffff0000'u64,
      0xffffffff'u64]:
    for alias in [false, true]:
      var part = @[op]
      if op <= 33:
        part.add(4)
        immediate(part, address)
        immediate(part, 0x89abcdef'u64)
      elif op >= 70 and op <= 73:
        part.add(79)
        immediate(part, 0)
        immediate(part, 0x89abcdef'u64)
      else:
        part.add(if op < 120: 15'u8 elif alias: 255'u8 else: 31'u8)
        immediate(part, if op < 120: address else: 0'u64)
      let program = owner([part, @[0'u8]])
      let prepared = cache(program)
      var selected = registers
      selected[1] = RegisterValue(address)
      if op >= 70 and op <= 73 or (op >= 120 and alias): selected[
          12] = RegisterValue(address)
      for access in [PageAccess.Inaccessible, PageAccess.ReadOnly,
          PageAccess.ReadWrite]:
        # Replacing the memory owner never changes prepared program facts or reuses old page permissions.
        var images = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped,
            PageIndex(17)).value]
        images[1].access = access
        let memory = captureMemory(images, PageLimit(2)).value
        let source = captureMachine(program, memory, MachineInfo(
            gas: MachineGas(1000), registers: selected)).value
        compare(source, prepared, 2, 100000)

# Host callbacks retain exact continuation, may replace memory, and cannot recursively enter the same cache identity.
type ReplyContext = object ## Test callback state contains only borrowed execution inputs and scalar progress.
  prepared, independent: PreparedProgram
  source: Machine
  calls, mode: int
  checkBusy: bool

proc reply(context: var ReplyContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Compare callback-visible state and exercise both same-owner refusal and independent nested execution.
  assert stopped.exit == StepExit.Host
  let state = machineInfo(stopped.machine).value
  if context.checkBusy:
    assert execute(context.source, ExecutionStepLimit(10),
        context.prepared).error ==StepError.PreparedProgramBusy
    assert execute(context.source, ExecutionStepLimit(10),
        context.independent).error == StepError.None
  inc context.calls
  var regs = state.registers
  regs[7] = RegisterValue(uint64(regs[7])+uint64(context.calls))
  let changed = store(memoryOf(stopped.machine).value, MemoryAddress(0x10fff),
      AccessWidth(8), regs[7])
  assert changed.error == MachineError.None
  let action = if context.mode == 1: HostAction.Uninitialized elif context.mode ==
      2: HostAction.Panic
    elif context.mode == 3: HostAction.OutOfGas elif context.mode ==
        4: HostAction.Halt else: HostAction.Continue
  HostResponse(action: action, gas: state.gas, gasDeficit: GasDeficit(
      if context.mode ==5: 1'u64 else: 0'u64), registers: regs,
          memory: changed.value)

type ReplyRefusal = enum Refused ## Enum ordinal zero remains a selected callback refusal.
proc fallibleReply(context: var ReplyContext, stopped: StepOutcome): HostResult[
    ReplyRefusal] {.raises: [].} =
  ## A selected refusal and an unselected default result must remain separate from engine/guest outcomes.
  if context.mode == 6: return hostFailure[ReplyRefusal](ReplyRefusal.Refused)
  if context.mode == 7: return default(HostResult[ReplyRefusal])
  hostSuccess[ReplyRefusal](reply(context, stopped))

let hostProgram = owner([@[10'u8, 13], @[10'u8, 14], @[0'u8]])
let hostCache = cache(hostProgram)
let nestedCache = cache(hostProgram)
let hostSource = captureMachine(hostProgram, mapped, MachineInfo(
    gas: MachineGas(10000), registers: registers)).value
for mode in 0..7:
  for calls in [0'u64, 1'u64, 2'u64]:
    # Identical callback effects and local budgets must agree on every ordinary and refusal path.
    var baseline = ReplyContext(source: hostSource, calls: 0, mode: mode,
        checkBusy: false)
    var candidate = ReplyContext(source: hostSource, calls: 0, mode: mode,
      checkBusy: true,
      prepared: hostCache, independent: nestedCache)
    if mode <= 5:
      let expected = executeWithHost(hostSource, baseline, reply,
          ExecutionStepLimit(10), HostCallLimit(calls), GasCycleLimit(100000))
      let actual = executeWithHost(hostSource, candidate, reply,
          ExecutionStepLimit(10), HostCallLimit(calls), hostCache)
      same(actual, expected)
    let expected = executeWithHost(hostSource, baseline, fallibleReply,
        ExecutionStepLimit(10), HostCallLimit(calls), GasCycleLimit(100000))
    let actual = executeWithHost(hostSource, candidate, fallibleReply,
        ExecutionStepLimit(10), HostCallLimit(calls), hostCache)
    assert actual.error == expected.error
    case actual.error
    of HostExecutionError.None:
      sameCpu(machineInfo(actual.value.machine).value, machineInfo(
          expected.value.machine).value)
      assert actual.value.exit == expected.value.exit
    of HostExecutionError.ExecutionFailure:
      assert actual.executionError == expected.executionError
    of HostExecutionError.HostFailure:
      assert actual.hostError == expected.hostError
    else: assert false
    # All success/failure callbacks release the outer busy flag before the next public call.
    assert execute(hostSource, ExecutionStepLimit(10), hostCache).error == StepError.None

# A paid fault retry may replace memory without changing the prepared operations or charging twice.
let faultProgram = owner([@[58'u8, 7, 0, 16, 1, 0], @[0'u8]])
let faultCache = cache(faultProgram)
let absent = captureMemory([], PageLimit(2)).value
let faultSource = captureMachine(faultProgram, absent, MachineInfo(
    gas: MachineGas(10000))).value
let fault = execute(faultSource, ExecutionStepLimit(5), faultCache)
assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
let repaired = captureMachine(faultProgram, mapped, machineInfo(
    fault.value.machine).value).value
compare(repaired, faultCache, 5, 100000)

proc lifecycle(input: Machine) =
  ## Prepared owners release their arrays and program references without retaining invocation snapshots or callbacks.
  let prepared = cache(programOf(input).value, blocks = 2)
  let first = execute(input, ExecutionStepLimit(5), prepared)
  let second = execute(input, ExecutionStepLimit(5), prepared)
  same(first, second)
let occupiedBefore = getOccupiedMem()
for cycle in 0..<1000:
  # Every private cache and completed outcome retires inside the bounded function call.
  lifecycle(firstSource)
let occupiedAfter = getOccupiedMem()
assert occupiedBefore == occupiedAfter
recordArcRelease("pvm_prepared_blocks", 1000, occupiedBefore, occupiedAfter)
echo "PVM prepared opcode and segment parity passed"
echo "ARC_RELEASE cycles=1000 unchanged"
