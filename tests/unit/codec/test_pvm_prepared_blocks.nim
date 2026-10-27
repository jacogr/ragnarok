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

proc cache(program: Program, cycles: uint64 = 100000, nodes: uint64 = 1048576): PreparedProgram =
  ## Explicit node/work bounds replace the removed byte/LRU cache; admitted facts do not emit executable nodes.
  var limits = defaultPreparedLimits(GasCycleLimit(cycles))
  limits.resources.nodes = ExecutionNodeLimit(nodes)
  let created = newPreparedProgram(program, limits)
  assert created.error == PreparationError.None
  assert preparedInfo(created.value).value.streamNodes == 0
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
  ## Cold and reused execution compare fresh and retained-cache calls, retaining the original source snapshot.
  let before = machineInfo(input).value
  let expected = execute(input, ExecutionStepLimit(steps), GasCycleLimit(cycles))
  for repeat in 0..<2:
    # Repeated calls share only prepared facts and always start from the same immutable machine.
    let actual = execute(input, ExecutionStepLimit(steps), prepared)
    same(actual, expected)
    sameCpu(machineInfo(input).value, before)
  let observed = preparedInfo(prepared).value
  assert observed.streamNodes <= uint64(observed.limits.resources.nodes)
  assert observed.preparationUnits <= uint64(observed.limits.resources.preparation)

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

proc registerPrefixMatrix() =
  ## Every literal register opcode precedes every genuine second opcode; budgets distinguish original and paired dispatch.
  var initial = default(RegisterFile)
  for index in 0..<13:
    # Mapped address-like values permit real loads/stores as well as arithmetic-generated faults and aliasing.
    initial[index] = RegisterValue(65536'u64+uint64(index)*16)
  var prefixes = 0
  for firstCode in 0..255:
    if byte(firstCode) in {20'u8, 51'u8, 100'u8..110'u8, 131'u8..161'u8, 190'u8..230'u8}:
      inc prefixes
      for secondCode in 0..255:
        if validOpcode(byte(secondCode)):
          # Deliberately aliased register descriptors expose any second-input read moved before the first mutation.
          var first = @[byte(firstCode)]
          var second = @[byte(secondCode)]
          for index in 0..<24:
            first.add(17'u8)
            second.add(17'u8)
          let program = owner([first, second, @[0'u8]])
          let prepared = cache(program, nodes = 4096)
          let source = captureMachine(program, mapped, MachineInfo(gas: MachineGas(100000),
            blockCharged: true, registers: initial)).value
          for steps in [1'u64, 2, 3]:
            # One attempt must not execute the second instruction; three observes both successful effects at the final trap.
            compare(source, prepared, steps, 100000)
  assert prefixes == 85

registerPrefixMatrix()

proc registerPrefixBytePressure() =
  ## Bounded node profiles cover adjacent add/load cells; aliasing and mapped-page endpoints expose premature pairing.
  let program = owner([@[149'u8, 0x77, 1], @[130'u8, 0x77, 0], @[0'u8]])
  for nodes in [32'u64, 1048576]:
    # Both both node profiles and ordinary two-cell dispatch preserve the same checked memory and attempt semantics.
    let prepared = cache(program, nodes = nodes)
    for address in [65536'u64, 69630, 73726]:
      var initial = default(RegisterFile)
      initial[7] = RegisterValue(address)
      let source = captureMachine(program, mapped, MachineInfo(gas: MachineGas(100000),
        blockCharged: true, registers: initial)).value
      for steps in 0'u64..4'u64:
        # Zero/one attempts cannot perform the second load; crossing the last mapped page must retain its exact fault.
        compare(source, prepared, steps, 100000)

registerPrefixBytePressure()

# Compact dynamic operands must read an aliased original base before the unconditional load mutation.
for descriptor in [119'u8, 255'u8]:
  # Both ordinary and saturated encoded register pairs deliberately select the same source/destination.
  let index = if descriptor == 119: 7 else: 12
  for offset in [0'u8, 1'u8, 255'u8]:
    # A signed one-byte offset exercises low32 wrapping before sentinel/alignment/table selection.
    let dynamicProgram = owner([@[180'u8, descriptor, 1, 90, offset], @[0'u8]])
    let dynamicCache = cache(dynamicProgram)
    for base in [0'u64, 1'u64, 2'u64, 0xffff0000'u64, 0xfffeffff'u64,
        0xffff0001'u64, 0x1ffff0000'u64, high(uint64)]:
      # Empty jump tables distinguish the halt sentinel from every other address without relying on another engine.
      var original = default(RegisterFile)
      original[index] = RegisterValue(base)
      let input = captureMachine(dynamicProgram, mapped, MachineInfo(gas: MachineGas(100),
        registers: original)).value
      let signedOffset = if offset == 255: high(uint64) else: uint64(offset)
      let address = (base+signedOffset) and 0xffffffff'u64
      let expected = if address == 0xffff0000'u64: StepExit.Halt else: StepExit.Panic
      compare(input, dynamicCache, 1, 100000)
      let result = execute(input, ExecutionStepLimit(1), dynamicCache)
      assert result.error == StepError.None and result.value.exit == expected
      assert uint64(machineInfo(result.value.machine).value.registers[index]) == 90
      assert uint64(machineInfo(input).value.registers[index]) == base

# Long straight-line blocks cross the fixed preparation-segment capacity while paying one complete block price.
var longParts: seq[seq[byte]] = @[]
for index in 0..<700:
  # Load-immediate is a genuine nonterminator with an independently known final register value.
  longParts.add(@[51'u8, 7, byte(index mod 127)])
longParts.add(@[0'u8])
let longProgram = owner(longParts)
let longCache = cache(longProgram, nodes = 4096)
let longPrice = uint64(blockGas(longProgram, CodeAddress(0), GasCycleLimit(100000)).value)
for gas in [longPrice-1, longPrice, longPrice+1, 1'u64 shl 63, high(uint64)]:
  let source = captureMachine(longProgram, mapped, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(gas), registers: registers)).value
  compare(source, longCache, 701, 100000)
assert preparedInfo(longCache).value.streamNodes >= 701
assert preparedInfo(longCache).value.decodedInstructions >= 701
# A stable-offset stream refuses a whole suffix before emission; local refusal publishes no partial machine.
let bounded = cache(longProgram, nodes = 8)
let boundedSource = captureMachine(longProgram, mapped, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(longPrice), registers: registers)).value
assert execute(boundedSource, ExecutionStepLimit(701), bounded).error ==
    StepError.InvalidPreparedProgram
assert preparedInfo(bounded).value.streamNodes == 0
assert uint64(machineInfo(boundedSource).value.gas) == longPrice
let longSource = captureMachine(longProgram, mapped, MachineInfo(
    pc: CodeAddress(0),
  gas: MachineGas(longPrice), registers: registers)).value
for steps in [0'u64, 1'u64, 255'u64, 256'u64, 257'u64, 700'u64]:
  # A local budget boundary cannot publish a prefix even when preparation already completed a segment.
  compare(longSource, longCache, steps, 100000)

# Every exhaustion point in the long block crosses the same retained array without spending an ungranted attempt.
for steps in 0'u64..702'u64:
  # The ordinary interpreter independently establishes exact state and refusal semantics at every cutoff.
  compare(longSource, longCache, steps, 100000)

# Program identity is exact: independently captured equal bytes cannot share prepared capabilities.
let first = owner([@[51'u8, 7, 11], @[0'u8]])
let second = owner([@[51'u8, 7, 11], @[0'u8]])
let firstCache = cache(first)
let wrongSource = captureMachine(second, mapped, MachineInfo(gas: MachineGas(100))).value
assert execute(wrongSource, ExecutionStepLimit(5), firstCache).error ==
    StepError.InvalidPreparedProgram
let absentPrepared = execute(wrongSource, ExecutionStepLimit(5), default(
    PreparedProgram))
assert absentPrepared.error == StepError.InvalidPreparedProgram
assert preparedInfo(default(PreparedProgram)).error ==
    PreparationError.InvalidProgram
assert newPreparedProgram(default(Program), PreparedLimits()).error ==
    PreparationError.InvalidProgram
var refusedLimits = defaultPreparedLimits()
refusedLimits.resources.codeBytes = ProgramByteLimit(0)
assert newPreparedProgram(first, refusedLimits).error == PreparationError.LimitExceeded
refusedLimits = defaultPreparedLimits()
refusedLimits.resources.facts = ExecutionFactLimit(0)
assert newPreparedProgram(first, refusedLimits).error == PreparationError.LimitExceeded
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
          let prepared = cache(program, nodes = 4096)
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

proc targetWorkingProgram(count: int, aliasedLoad: bool): Program =
  ## Three complete rounds visit every dynamic destination; final probes collide with valid ordinal tags after the cache is warm.
  var parts: seq[seq[byte]] = @[]
  var jumps: seq[uint32] = @[]
  let transferBytes = if aliasedLoad: 11 else: 6
  let blockBytes = 9+transferBytes
  for index in 0..<count:
    # Register7 counts actual visits; register9 independently accumulates destination identities.
    jumps.add(uint32(index*blockBytes))
    parts.add(@[149'u8, 0x77, 1])
    var checksum = @[149'u8, 0x99]
    immediate(checksum, uint64(index+1))
    parts.add(checksum)
    let ordinalAddress = if index+1 == count: 2'u64 else: uint64((index+2)*2)
    var transfer: seq[byte] = @[]
    if aliasedLoad:
      # The old base must be read before replacing that same register; offsets deliberately include negative signed-four-byte values.
      transfer = @[180'u8, 0x66, 4]
      immediate(transfer, uint64((index+1)*2))
      let priorBase = if index == 0: uint64(count*2) else: uint64(index*2)
      immediate(transfer, (ordinalAddress+0x100000000'u64-priorBase) and 0xffffffff'u64)
    else:
      # A zero base plus the literal two-byte-aligned selector visits the next original table entry.
      transfer = @[50'u8, 6]
      immediate(transfer, ordinalAddress)
    if index+1 == count:
      # Equality exits only after exactly three rounds; both branch destinations are genuine basic-block starts.
      var finish = @[170'u8, 0x87]
      immediate(finish, uint64(6+transferBytes))
      parts.add(finish)
    parts.add(transfer)
  parts.add(@[50'u8, 0]) # Register0 chooses halt, malformed address, invalid target or colliding out-of-table ordinal after warmup.
  parts.add(@[0'u8])
  jumps.add(3'u32) # Marked second arithmetic instruction is inside a block, never a legal dynamic target.
  jumps.add(1'u32) # Operand byte is unmarked.
  jumps.add(uint32(count*blockBytes+100)) # Beyond the complete code extent.
  owner(parts, jumps)

proc targetWorkingSource(program: Program, count: int, aliasedLoad: bool,
    selector: uint64): Machine =
  ## Source-owned registers choose the probe independently of cache contents and retain a predictable final counter/checksum.
  var initial = default(RegisterFile)
  initial[0] = RegisterValue(selector)
  initial[6] = RegisterValue(if aliasedLoad: uint64(count*2) else: 0'u64)
  initial[8] = RegisterValue(uint64(count*3))
  captureMachine(program, mapped, MachineInfo(gas: MachineGas(1000000), registers: initial)).value

proc dynamicTargetWorkingSets() =
  ## Exact full ordinal tags reject collisions across both small and expanded bounded cache capacities, including first-failing target validation.
  for count in [5, 17, 65, 257, 513]:
    for aliasedLoad in [false, true]:
      let program = targetWorkingProgram(count, aliasedLoad)
      let prepared = cache(program)
      for selector in [0xffff0000'u64, 0, 1, uint64((count+1)*2), uint64((count+2)*2),
          uint64((count+3)*2), uint64((count+514)*2)]:
        # The final out-of-table ordinal aliases a populated slot modulo512; no partial/tag-only match may authorize it.
        let source = targetWorkingSource(program, count, aliasedLoad, selector)
        compare(source, prepared, 100000, 100000)
        let actual = execute(source, ExecutionStepLimit(100000), prepared)
        assert actual.error == StepError.None
        assert actual.value.exit == (if selector ==
            0xffff0000'u64: StepExit.Halt else: StepExit.Panic)
        let state = machineInfo(actual.value.machine).value
        assert uint64(state.pc) == 0
        assert uint64(state.registers[7]) == uint64(count*3)
        assert uint64(state.registers[9]) == uint64(3*count*(count+1) div 2)
        assert uint64(state.registers[6]) == (if aliasedLoad: uint64((count-1)*2) else: 0'u64)
      let source = targetWorkingSource(program, count, aliasedLoad, 0xffff0000'u64)
      for steps in [0'u64, 1, 2, 3, 4, 40, 80]:
        # Attempt exhaustion before/after a large target working set remains a local failure with the same retained immutable source.
        compare(source, prepared, steps, 100000)

dynamicTargetWorkingSets()

proc dynamicTargetLifecycle(input: Machine, prepared: PreparedProgram) =
  ## A collision-heavy invocation retires its target facts on both completed and scheduling-failure exits.
  let complete = execute(input, ExecutionStepLimit(100000), prepared)
  assert complete.error == StepError.None and complete.value.exit == StepExit.Halt
  assert execute(input, ExecutionStepLimit(80), prepared).error == StepError.StepLimitExceeded

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
    let nestedBusy = execute(context.source, ExecutionStepLimit(10),
        context.prepared)
    assert nestedBusy.error == StepError.PreparedProgramBusy
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
  let deficit = if context.mode == 5: 1'u64 else: 0'u64
  HostResponse(action: action, gas: state.gas, gasDeficit: GasDeficit(deficit),
    registers: regs, memory: changed.value)

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

type MemoryPrefixContext = object ## Only callback progress escapes a successful checked load/host pair.
  calls: int
proc memoryPrefixReply(context: var MemoryPrefixContext,
    stopped: StepOutcome): HostResponse {.raises: [].} =
  ## An independent byte-level expectation identifies the exact second source site and the first load's visible result.
  assert stopped.exit == StepExit.Host
  assert uint64(stopped.hostCall) == 13
  let state = machineInfo(stopped.machine).value
  assert uint64(state.pc) == 6
  assert uint64(state.registers[1]) == 0x7a69584736251403'u64
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: state.gas, registers: state.registers,
    memory: memoryOf(stopped.machine).value)

proc memoryPrefixHostBudgets() =
  ## A first fault cannot reach the callback; a successful pair debits exactly two attempts before host continuation.
  for address in [65536'u64, 73727]:
    let program = owner([firstMemoryPart(58, address), @[10'u8, 13], @[51'u8, 7, 22], @[0'u8]])
    for nodes in [32'u64, 1048576]:
      # Both node profiles and ordinary retained pairing share all observable callback/budget boundaries.
      let prepared = cache(program, nodes = nodes)
      for gas in [0'u64, 1, 100000]:
        let source = captureMachine(program, mapped, MachineInfo(gas: MachineGas(gas))).value
        for steps in 0'u64..5'u64:
          for calls in 0'u64..1'u64:
            var baseline = MemoryPrefixContext(calls: 0)
            var candidate = MemoryPrefixContext(calls: 0)
            let expected = executeWithHost(source, baseline, memoryPrefixReply,
              ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(100000))
            let actual = executeWithHost(source, candidate, memoryPrefixReply,
              ExecutionStepLimit(steps), HostCallLimit(calls), prepared)
            same(actual, expected)
            assert candidate.calls == baseline.calls

memoryPrefixHostBudgets()

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

proc positionPrefix(): seq[seq[byte]] =
  ## Cross a 256-operation segment before observing any byte PC; every load has a known original instruction width.
  result = @[]
  for index in 0..<257:
    # The final loaded value remains visible at all later suspension/gas boundaries.
    result.add(@[51'u8, 7, 11])

type PositionContext = object ## Callback observations depend on immutable fixture byte positions, not another interpreter.
  calls: int
proc positionReply(context: var PositionContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Assert the causing byte PC after a segment split and again after a resumed ordinary prefix.
  let state = machineInfo(stopped.machine).value
  assert context.calls in [0, 1]
  assert uint64(state.pc) == (if context.calls == 0: 771'u64 else: 777'u64)
  assert uint64(state.registers[7]) == (if context.calls == 0: 11'u64 else: 22'u64)
  assert uint64(stopped.hostCall) == uint64(13+context.calls)
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: state.gas, registers: state.registers,
    memory: memoryOf(stopped.machine).value)

var positionParts = positionPrefix()
positionParts.add(@[10'u8, 13])
positionParts.add(@[2'u8])
positionParts.add(@[51'u8, 7, 22])
positionParts.add(@[10'u8, 14])
positionParts.add(@[0'u8])
let positionProgram = owner(positionParts)
let positionCache = cache(positionProgram, nodes = 4096)
let positionSource = captureMachine(positionProgram, mapped,
  MachineInfo(gas: MachineGas(100000))).value
for steps in [0'u64, 1, 255, 256, 257, 258, 259, 260, 261, 262]:
  for calls in [0'u64, 1, 2]:
    # Attempt exhaustion immediately before/after each host must consume exactly the executed prefix, even on cache reuse.
    var ordinary = PositionContext(calls: 0)
    var prepared = PositionContext(calls: 0)
    let expected = executeWithHost(positionSource, ordinary, positionReply,
      ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(100000))
    let actual = executeWithHost(positionSource, prepared, positionReply,
      ExecutionStepLimit(steps), HostCallLimit(calls), positionCache)
    same(actual, expected)
    let firstCall = if steps >= 258 and calls >= 1: 1 else: 0
    let secondCall = if steps >= 261 and calls >= 2: 1 else: 0
    assert ordinary.calls == firstCall+secondCall and prepared.calls == ordinary.calls
    let reason = if steps >= 258 and calls == 0 or steps >= 261 and calls == 1:
        StepError.HostCallLimitExceeded
      elif steps == 262: StepError.None else: StepError.StepLimitExceeded
    assert actual.error == reason
    sameCpu(machineInfo(positionSource).value, MachineInfo(gas: MachineGas(100000)))

var faultPositionParts = positionPrefix()
faultPositionParts.add(@[58'u8, 8, 0, 16, 1, 0])
faultPositionParts.add(@[0'u8])
let faultPositionProgram = owner(faultPositionParts)
let faultPositionCache = cache(faultPositionProgram, nodes = 4096)
let faultPositionSource = captureMachine(faultPositionProgram, absent,
  MachineInfo(gas: MachineGas(100000))).value
for steps in [255'u64, 256, 257, 258, 259]:
  # A fault after ordinary work reconstructs its own byte PC instead of the segment entry or last materialized successor.
  compare(faultPositionSource, faultPositionCache, steps, 100000)
let positionedFault = execute(faultPositionSource, ExecutionStepLimit(258), faultPositionCache)
assert positionedFault.error == StepError.None and positionedFault.value.exit == StepExit.Fault
let stoppedPosition = machineInfo(positionedFault.value.machine).value
assert uint64(stoppedPosition.pc) == 771 and uint64(stoppedPosition.registers[7]) == 11
assert stoppedPosition.blockCharged and uint32(positionedFault.value.faultPage) == 0x11000
let positionRepair = captureMachine(faultPositionProgram, mapped, stoppedPosition).value
compare(positionRepair, faultPositionCache, 2, 100000)
let finishedRepair = execute(positionRepair, ExecutionStepLimit(2), faultPositionCache)
assert finishedRepair.error == StepError.None and finishedRepair.value.exit == StepExit.Panic
assert uint64(machineInfo(finishedRepair.value.machine).value.gas) == uint64(stoppedPosition.gas)

var gasPositionParts = positionPrefix()
gasPositionParts.add(@[1'u8])
gasPositionParts.add(@[51'u8, 7, 22])
gasPositionParts.add(@[0'u8])
let gasPositionProgram = owner(gasPositionParts)
let gasPositionCache = cache(gasPositionProgram, nodes = 4096)
let entryPrice = uint64(blockGas(gasPositionProgram, CodeAddress(0), GasCycleLimit(100000)).value)
let gasPositionSource = captureMachine(gasPositionProgram, mapped,
  MachineInfo(gas: MachineGas(entryPrice))).value
for steps in [257'u64, 258, 259]:
  # Exhaustion at the transfer differs from reaching the next uncharged block with no affordable gas.
  compare(gasPositionSource, gasPositionCache, steps, 100000)
let positionedGas = execute(gasPositionSource, ExecutionStepLimit(259), gasPositionCache)
assert positionedGas.error == StepError.None and positionedGas.value.exit == StepExit.OutOfGas
let gasPosition = machineInfo(positionedGas.value.machine).value
assert uint64(gasPosition.pc) == 772 and uint64(gasPosition.gas) == 0
assert not gasPosition.blockCharged and uint64(gasPosition.registers[7]) == 11

proc successorEvictionCycle() =
  ## Stable source offsets retain the correct destination across distinct entry points and repeated leases.
  let program = owner([@[40'u8, 3], @[0'u8], @[51'u8, 7, 99], @[0'u8],
    @[51'u8, 7, 55], @[0'u8]])
  let prepared = cache(program, nodes = 4096)
  let entry = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(100))).value
  let replacement = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(7),
    gas: MachineGas(100))).value
  for repeat in 0..<4:
    # Marked entries0/3/7 exercise distinct entries; every retained target remains bound to the exact source PC.
    compare(entry, prepared, 4, 100000)
    compare(replacement, prepared, 4, 100000)
    compare(entry, prepared, 4, 100000)
    let final = execute(entry, ExecutionStepLimit(4), prepared)
    assert final.error == StepError.None and final.value.exit == StepExit.Panic
    assert uint64(machineInfo(final.value.machine).value.registers[7]) == 99
  assert preparedInfo(prepared).value.streamNodes > 0
  for gas in [0'u64, 1, 2, 3, 4]:
    # Budget and gas exits keep their exact precharge and causing-PC semantics even with learned links.
    let source = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(gas))).value
    for steps in [0'u64, 1, 2, 3, 4]: compare(source, prepared, steps, 100000)

proc sealedTerminatorCycle() =
  ## A genuine branch jumps over a mutating instruction to the block following a trap; no sealed array runs past its terminator.
  let program = owner([@[51'u8, 7, 1], @[40'u8, 6], @[51'u8, 7, 99], @[0'u8], @[0'u8]])
  let prepared = cache(program, nodes = 4096)
  for paid in [false, true]:
    for gas in [0'u64, 1, 2, 3, 4, 10, 100000]:
      # Exact charge and attempt boundaries must preserve the selected path on both cold and reused arrays.
      let source = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(0),
        gas: MachineGas(gas), blockCharged: paid)).value
      for steps in [0'u64, 1, 2, 3, 4, 5]: compare(source, prepared, steps, 100000)
  let source = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(100000))).value
  let final = execute(source, ExecutionStepLimit(4), prepared)
  assert final.error == StepError.None and final.value.exit == StepExit.Panic
  assert uint64(machineInfo(final.value.machine).value.registers[7]) == 1

sealedTerminatorCycle()
successorEvictionCycle()

proc lifecycle(input: Machine) =
  ## Prepared owners release their arrays and program references without retaining invocation snapshots or callbacks.
  let prepared = cache(programOf(input).value, nodes = 4096)
  let first = execute(input, ExecutionStepLimit(5), prepared)
  let second = execute(input, ExecutionStepLimit(5), prepared)
  same(first, second)
let targetArcProgram = targetWorkingProgram(17, true)
let targetArcSource = targetWorkingSource(targetArcProgram, 17, true, 0xffff0000'u64)
let targetArcCache = cache(targetArcProgram)
dynamicTargetLifecycle(targetArcSource, targetArcCache) # Settle the retained chunk working set before measuring invocation-owned allocations.
let occupiedBefore = getOccupiedMem()
for cycle in 0..<1000:
  # Every private cache and completed outcome retires inside the bounded function call.
  lifecycle(firstSource)
  dynamicTargetLifecycle(targetArcSource, targetArcCache) # Both successful and failed invocations retire target facts without retaining source or cache owners.
  successorEvictionCycle() # Scalar links never retain a destination owner or form a cycle.
let occupiedAfter = getOccupiedMem()
assert occupiedBefore == occupiedAfter
recordArcRelease("pvm_prepared_blocks", 1000, occupiedBefore, occupiedAfter)
echo "PVM prepared opcode and segment parity passed"
echo "ARC_RELEASE cycles=1000 unchanged"
