# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Differential memory/host witnesses and full-execution timings using program-owned preparation.
import std/[assertions, syncio, monotimes, envvars]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas]
import ../../src/pvm/step as reference
import ../../build/pvm-ir-experiment/shared_step as prepared

proc cpuNanoseconds(): int64 {.importc: "pvm_ir_cpu_nanoseconds", header: "cpu_clock.h".}
  ## The existing OS helper separates process CPU time from elapsed scheduling time.

type
  Guest = object ## One memory read/modify/write loop, optionally suspending before its backedge.
    owner: Program
    extra, add, loadPc, storePc, hostPc, counterPc, branchPc, haltPc, attempts: int
    hosted: bool
    price, haltPrice: uint64
  Reply {.pure.} = enum ## Local test modes select ordinary and deliberately invalid host replies.
    Continue, Panic, OutOfGas, Halt, Uninitialized, BadMemory, Debt, ReplaceMemory
  Context = object ## Callback effects remain observable even when a later host response is refused.
    calls: int
    reply: Reply
  Observation = object ## Test-only normalized state; payload fields are inspected only on success.
    error, exit: int
    info: MachineInfo
    memory: Memory
    detail: uint64

proc blob(code: seq[byte], starts: seq[int]): Program =
  ## Frame explicit instructions independently of the production operand decoder.
  let size = encode(JamNatural(code.len))
  var wire: seq[byte] = @[0'u8, 0'u8]
  for i in 0..<size.len: wire.add(size.bytes[i])
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  for pc in starts: mask[pc div 8] = mask[pc div 8] or byte(1 shl (pc mod 8))
  for value in mask: wire.add(value)
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(8192), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  result = decoded.value

proc guest(extra: int, hosted: bool, add: byte): Guest =
  ## r7 addresses memory, r8 holds the scalar, r9 counts loops, r10 halts, r11 bounds loops.
  assert extra >= 0 and extra <= 32 and add in [1'u8, 3'u8]
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for i in 0..<extra:
    # Additional real arithmetic operations expose a larger decoder working set.
    starts.add(code.len)
    for value in [149'u8, 0x55'u8, 1'u8]: code.add(value)
  let loadPc = code.len
  starts.add(code.len)
  for value in [130'u8, 0x78'u8]: code.add(value)
  starts.add(code.len)
  for value in [149'u8, 0x88'u8, add]: code.add(value)
  let storePc = code.len
  starts.add(code.len)
  for value in [123'u8, 0x78'u8]: code.add(value)
  let hostPc = code.len
  if hosted:
    starts.add(code.len)
    for value in [10'u8, 7'u8]: code.add(value)
  let counterPc = code.len
  starts.add(code.len)
  for value in [149'u8, 0x99'u8, 1'u8]: code.add(value)
  let branchPc = code.len
  starts.add(code.len)
  for value in [172'u8, 0xb9'u8]: code.add(value)
  let offset = 0'u64 - uint64(branchPc)
  for i in 0..<4: code.add(byte((offset shr (8 * i)) and 255))
  let haltPc = code.len
  starts.add(code.len)
  for value in [50'u8, 10'u8]: code.add(value)
  let owner = blob(code, starts)
  let loopPrice = blockGas(owner, CodeAddress(0), GasCycleLimit(4096))
  let haltPrice = blockGas(owner, CodeAddress(haltPc), GasCycleLimit(4096))
  assert loopPrice.error == GasError.None and haltPrice.error == GasError.None
  result = Guest(owner: owner, extra: extra, add: int(add), hosted: hosted,
    loadPc: loadPc, storePc: storePc, hostPc: hostPc, counterPc: counterPc,
    branchPc: branchPc, haltPc: haltPc, attempts: extra + (if hosted: 6 else: 5),
    price: uint64(loopPrice.value), haltPrice: uint64(haltPrice.value))

proc plan(f: Guest): prepared.PreparedProgram =
  ## Preparation uses explicit bounds and never retains invocation registers or memory.
  let captured = prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(4096),
    prepared.PreparationInstructionLimit(256))
  assert captured.error == prepared.PreparationError.None
  result = captured.value

proc image(index: uint32, access: PageAccess, seed: byte): PageImage =
  ## Full-page patterns expose accidental writes outside the selected scalar bytes.
  result = PageImage(index: PageIndex(index), access: access, bytes: default(array[4096, byte]))
  for i in 0..<4096: result.bytes[i] = byte((int(seed) + i * 13) mod 256)

proc memoryFor(address, scalar: uint64, kind: int): Memory =
  ## Kinds: writable, missing first/second, read-only first/second, inaccessible second, protected.
  var pages: seq[PageImage] = @[]
  for n in 0..<2:
    if (kind != 1 or n != 0) and (kind != 2 or n != 1):
      var access = PageAccess.ReadWrite
      if (kind == 3 and n == 0) or (kind == 4 and n == 1): access = PageAccess.ReadOnly
      if kind == 5 and n == 1: access = PageAccess.Inaccessible
      var page = image(uint32(16 + n), access, byte(37 + n * 19))
      for i in 0..<8:
        # Seed the scalar directly in page images, including images not currently accessible.
        let physical = address + uint64(i)
        if physical div 4096 == uint64(16 + n):
          page.bytes[int(physical mod 4096)] = byte((scalar shr (8 * i)) and 255)
      pages.add(page)
  let captured = captureMemory(pages, PageLimit(2))
  assert captured.error == MachineError.None
  result = captured.value

proc infoFor(f: Guest, address, loops: uint64): MachineInfo =
  ## Exact successful runs retain seven gas after both guest charging and one gas per host reply.
  result = MachineInfo(pc: CodeAddress(0), gas: MachineGas(loops * f.price + f.haltPrice +
    (if f.hosted: loops else: 0'u64) + 7), registers: default(RegisterFile), blockCharged: false)
  result.registers[7] = RegisterValue(address)
  result.registers[10] = RegisterValue(0xffff0000'u64)
  result.registers[11] = RegisterValue(loops)

proc sameInfo(a, b: MachineInfo) =
  ## Compare complete CPU state, including the flag that prevents double charging after a fault.
  assert uint64(a.pc) == uint64(b.pc) and uint64(a.gas) == uint64(b.gas)
  assert uint64(a.gasDeficit) == uint64(b.gasDeficit) and a.blockCharged == b.blockCharged
  for i in 0..<13: assert uint64(a.registers[i]) == uint64(b.registers[i])

proc sameMemory(a, b: Memory) =
  ## Compare every byte and permission of both relevant pages, even when access is forbidden.
  for index in [16'u32, 17'u32]:
    let left = pageImage(a, PageIndex(index)).value
    let right = pageImage(b, PageIndex(index)).value
    assert left.access == right.access
    for i in 0..<4096: assert left.bytes[i] == right.bytes[i]

proc observe(r: reference.StepResult): Observation =
  ## Normalize production results only after selecting their guarded success alternative.
  result = Observation(error: ord(r.error))
  if r.error == reference.StepError.None:
    let value = r.value
    result.exit = ord(value.exit)
    result.info = machineInfo(value.machine).value
    result.memory = memoryOf(value.machine).value
    if value.exit == reference.StepExit.Fault: result.detail = uint64(uint32(value.faultPage))
    if value.exit == reference.StepExit.Host: result.detail = uint64(value.hostCall)

proc observe(r: prepared.StepResult): Observation =
  ## Normalize the generated module's distinct result/exit types without bypassing guards.
  result = Observation(error: ord(r.error))
  if r.error == prepared.StepError.None:
    let value = r.value
    result.exit = ord(value.exit)
    result.info = machineInfo(value.machine).value
    result.memory = memoryOf(value.machine).value
    if value.exit == prepared.StepExit.Fault: result.detail = uint64(uint32(value.faultPage))
    if value.exit == prepared.StepExit.Host: result.detail = uint64(value.hostCall)

proc same(a, b: Observation) =
  ## A local error exposes no state; successful guest exits must agree in every observable field.
  assert a.error == b.error
  if a.error == ord(reference.StepError.None):
    assert a.exit == b.exit and a.detail == b.detail
    sameInfo(a.info, b.info)
    sameMemory(a.memory, b.memory)

proc respond(context: var Context, stopped: reference.StepOutcome): reference.HostResponse {.raises: [].} =
  ## The host debits one gas and updates one register; invalid modes exercise response validation.
  inc context.calls
  let cpu = machineInfo(stopped.machine).value
  var registers = cpu.registers
  registers[6] = RegisterValue(context.calls)
  result = reference.HostResponse(action: reference.HostAction.Continue,
    gas: MachineGas(if uint64(cpu.gas) > 0: uint64(cpu.gas) - 1 else: 0'u64),
    registers: registers, memory: memoryOf(stopped.machine).value)
  case context.reply
  of Reply.Continue: discard
  of Reply.Panic: result.action = reference.HostAction.Panic
  of Reply.OutOfGas: result.action = reference.HostAction.OutOfGas
  of Reply.Halt: result.action = reference.HostAction.Halt
  of Reply.Uninitialized: result.action = reference.HostAction.Uninitialized
  of Reply.BadMemory: result.memory = default(Memory)
  of Reply.Debt: result.gasDeficit = GasDeficit(1)
  of Reply.ReplaceMemory:
    let changed = store(result.memory, MemoryAddress(uint64(cpu.registers[7])), AccessWidth(8),
        RegisterValue(77))
    assert changed.error == MachineError.None
    result.memory = changed.value

proc respond(context: var Context, stopped: prepared.StepOutcome): prepared.HostResponse {.raises: [].} =
  ## Supply identical effects through the generated module's own guarded host-response boundary.
  inc context.calls
  let cpu = machineInfo(stopped.machine).value
  var registers = cpu.registers
  registers[6] = RegisterValue(context.calls)
  result = prepared.HostResponse(action: prepared.HostAction.Continue,
    gas: MachineGas(if uint64(cpu.gas) > 0: uint64(cpu.gas) - 1 else: 0'u64),
    registers: registers, memory: memoryOf(stopped.machine).value)
  case context.reply
  of Reply.Continue: discard
  of Reply.Panic: result.action = prepared.HostAction.Panic
  of Reply.OutOfGas: result.action = prepared.HostAction.OutOfGas
  of Reply.Halt: result.action = prepared.HostAction.Halt
  of Reply.Uninitialized: result.action = prepared.HostAction.Uninitialized
  of Reply.BadMemory: result.memory = default(Memory)
  of Reply.Debt: result.gasDeficit = GasDeficit(1)
  of Reply.ReplaceMemory:
    let changed = store(result.memory, MemoryAddress(uint64(cpu.registers[7])), AccessWidth(8),
        RegisterValue(77))
    assert changed.error == MachineError.None
    result.memory = changed.value

proc baseline(f: Guest, memory: Memory, info: MachineInfo, steps, cycles, calls: uint64,
    context: var Context): Observation =
  ## Both engines include the same source-snapshot construction in measured invocations.
  let source = captureTerminalMachine(f.owner, memory, info)
  if source.error != MachineError.None: return Observation(error: ord(
      reference.StepError.InvalidMachine))
  if f.hosted:
    return observe(reference.executeWithHost(source.value, context, respond,
      reference.ExecutionStepLimit(steps), reference.HostCallLimit(calls), GasCycleLimit(cycles)))
  observe(reference.execute(source.value, reference.ExecutionStepLimit(steps), GasCycleLimit(cycles)))

proc candidate(f: Guest, table: prepared.PreparedProgram, memory: Memory, info: MachineInfo,
    steps, cycles, calls: uint64, context: var Context): Observation =
  ## Program identity comes exclusively from the table; invocation state contains no program handle.
  if f.hosted:
    return observe(prepared.executeSharedWithHost(table, memory, info, context, respond,
      prepared.ExecutionStepLimit(steps), prepared.HostCallLimit(calls), GasCycleLimit(cycles)))
  observe(prepared.executeShared(table, memory, info, prepared.ExecutionStepLimit(steps),
      GasCycleLimit(cycles)))

proc complete(f: Guest, observed: Observation, original: MachineInfo,
    address, seed, loops: uint64) =
  ## Independently derive successful registers, gas and the full expected byte images.
  assert observed.error == ord(reference.StepError.None) and observed.exit == ord(
      reference.StepExit.Halt)
  var expected = original
  expected.pc = CodeAddress(0)
  expected.gas = MachineGas(7)
  expected.blockCharged = true
  expected.registers[5] = RegisterValue(uint64(f.extra) * loops)
  expected.registers[6] = RegisterValue(if f.hosted: loops else: 0'u64)
  expected.registers[8] = RegisterValue(seed + loops * uint64(f.add))
  expected.registers[9] = RegisterValue(loops)
  sameInfo(observed.info, expected)
  sameMemory(observed.memory, memoryFor(address, seed + loops * uint64(f.add), 0))

proc padded(count: int, stride: int = 1): Program =
  ## Valid no-op code provides independent hard-cap witnesses without large allocations.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for i in 0..<count:
    starts.add(code.len)
    code.add(2)
    for gap in 1..<stride: code.add(0)
  starts.add(code.len)
  for value in [50'u8, 10'u8]: code.add(value)
  for gap in 2..<stride: code.add(0)
  blob(code, starts)

proc preparationChecks(): int =
  ## Test defaults, exact/one-less limits and hard caps before using any shared executable owner.
  let f = guest(0, true, 1)
  let size = codeLength(f.owner).value
  let count = uint64(f.attempts + 1)
  assert prepared.prepareProgram(default(Program), prepared.PreparationByteLimit(4096),
    prepared.PreparationInstructionLimit(256)).error == prepared.PreparationError.InvalidProgram
  assert prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(size - 1),
    prepared.PreparationInstructionLimit(count)).error ==
        prepared.PreparationError.ByteLimitExceeded
  assert prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(size),
    prepared.PreparationInstructionLimit(count - 1)).error ==
        prepared.PreparationError.InstructionLimitExceeded
  assert prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(size),
    prepared.PreparationInstructionLimit(count)).error == prepared.PreparationError.None
  assert prepared.prepareProgram(padded(256), prepared.PreparationByteLimit(4096),
    prepared.PreparationInstructionLimit(high(uint64))).error ==
        prepared.PreparationError.InstructionLimitExceeded
  assert prepared.prepareProgram(padded(4095), prepared.PreparationByteLimit(high(uint64)),
    prepared.PreparationInstructionLimit(high(uint64))).error ==
        prepared.PreparationError.ByteLimitExceeded
  let empty = default(prepared.PreparedProgram)
  assert prepared.executeShared(empty, memoryFor(0x10000, 9, 0), infoFor(f, 0x10000, 1),
    prepared.ExecutionStepLimit(1), GasCycleLimit(4096)).error == prepared.StepError.InvalidMachine
  assert prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(0),
    prepared.PreparationInstructionLimit(256)).error == prepared.PreparationError.ByteLimitExceeded
  assert prepared.prepareProgram(f.owner, prepared.PreparationByteLimit(4096),
    prepared.PreparationInstructionLimit(0)).error ==
        prepared.PreparationError.InstructionLimitExceeded
  var context = Context(calls: 0, reply: Reply.Continue)
  assert prepared.executeSharedWithHost(empty, memoryFor(0x10000, 9, 0),
    infoFor(f, 0x10000, 1), context, respond, prepared.ExecutionStepLimit(10),
    prepared.HostCallLimit(1), GasCycleLimit(4096)).error == prepared.StepError.InvalidMachine
  assert context.calls == 0
  # Exactly 4096 code bytes and 256 records exercise the largest supported lookup/index value.
  let maximumOwner = padded(255, 16)
  let maximum = prepared.prepareProgram(maximumOwner, prepared.PreparationByteLimit(4096),
    prepared.PreparationInstructionLimit(256))
  assert maximum.error == prepared.PreparationError.None
  assert prepared.preparedBytes(maximum.value) == 4096 * 2 + 256 * sizeof(ProgramResult[Instruction])
  let memory = captureMemory([], PageLimit(0)).value
  var info = infoFor(f, 0x10000, 1)
  info.blockCharged = true
  let original = captureMachine(maximumOwner, memory, info).value
  let expected = observe(reference.execute(original, reference.ExecutionStepLimit(256),
      GasCycleLimit(0)))
  let actual = observe(prepared.executeShared(maximum.value, memory, info,
    prepared.ExecutionStepLimit(256), GasCycleLimit(0)))
  same(actual, expected)
  assert actual.exit == ord(reference.StepExit.Halt) and uint64(actual.info.gas) == uint64(info.gas)
  result = 11

proc memoryChecks(): int =
  ## Compare fault metadata, atomic memory effects, charging and retries over shared program tables.
  result = 0
  let f = guest(0, false, 1)
  let table = plan(f)
  for address in [0x10000'u64, 0x10ffc'u64, 0x3000'u64]:
    for kind in 0..5:
      let memory = memoryFor(address, 9, kind)
      let original = infoFor(f, address, 1)
      for charged in [false, true]:
        for balance in [0'u64, f.price - 1, uint64(original.gas)]:
          var info = original
          info.gas = MachineGas(balance)
          info.blockCharged = charged
          for steps in [0'u64, 1'u64, uint64(f.attempts), uint64(f.attempts + 1)]:
            for cycles in [0'u64, 4096'u64]:
              var left = Context(calls: 0, reply: Reply.Continue)
              var right = Context(calls: 0, reply: Reply.Continue)
              same(baseline(f, memory, info, steps, cycles, 0, left),
                candidate(f, table, memory, info, steps, cycles, 0, right))
              sameMemory(memory, memoryFor(address, 9, kind))
              inc result
  for kind in [1, 2, 3, 4, 5]:
    # Repair the exact faulting page, preserving every previously published byte and charged flag.
    let address = 0x10ffc'u64
    let memory = memoryFor(address, 9, kind)
    let original = infoFor(f, address, 1)
    var left = Context(calls: 0, reply: Reply.Continue)
    var right = Context(calls: 0, reply: Reply.Continue)
    let failed = baseline(f, memory, original, 20, 4096, 0, left)
    let candidateFailed = candidate(f, table, memory, original, 20, 4096, 0, right)
    same(failed, candidateFailed)
    assert failed.exit == ord(reference.StepExit.Fault) and failed.info.blockCharged
    assert uint64(failed.info.gas) == uint64(original.gas) - f.price
    assert uint64(failed.info.pc) == uint64(if kind in [3, 4]: f.storePc else: f.loadPc)
    assert failed.detail == (if kind in [1, 3]: 0x10000'u64 else: 0x11000'u64)
    sameMemory(failed.memory, memory)
    let good = memoryFor(address, 9, 0)
    let repairPage = pageImage(good, PageIndex(uint32(failed.detail div 4096))).value
    let repaired = withPage(failed.memory, repairPage).value
    # A prepaid retry with zero simulation cycles must attempt work rather than reprice the block.
    let limited = baseline(f, repaired, failed.info, 1, 0, 0, left)
    same(limited, candidate(f, table, repaired, candidateFailed.info, 1, 0, 0, right))
    assert limited.error == ord(reference.StepError.StepLimitExceeded)
    sameMemory(repaired, memoryFor(address, 9, 0))
    inc result
    let resumed = baseline(f, repaired, failed.info, 20, 4096, 0, left)
    let candidateResumed = candidate(f, table, repaired, candidateFailed.info, 20, 4096, 0, right)
    same(resumed, candidateResumed)
    complete(f, resumed, original, address, 9, 1)
    sameMemory(memory, memoryFor(address, 9, kind))
    sameMemory(failed.memory, memory)
    inc result

proc orphanPlan(): prepared.PreparedProgram =
  ## The original local Program handle retires here; the prepared table must retain its owner.
  let local = guest(0, true, 1)
  plan(local)

proc hostChecks(): int =
  ## Exercise host-call budgets, terminal replies, invalid responses and program-table reuse.
  result = 0
  let f = guest(0, true, 1)
  let table = plan(f)
  for address in [0x10000'u64, 0x10ffc'u64]:
    let memory = memoryFor(address, 9, 0)
    let original = infoFor(f, address, 3)
    for reply in [Reply.Continue, Reply.Panic, Reply.OutOfGas, Reply.Halt,
        Reply.Uninitialized, Reply.BadMemory, Reply.Debt, Reply.ReplaceMemory]:
      for permitted in [0'u64, 1'u64, 3'u64]:
        for steps in [0'u64, 4'u64, 18'u64, 19'u64]:
          for cycles in [0'u64, 4096'u64]:
            for balance in [0'u64, uint64(original.gas)]:
              var info = original
              info.gas = MachineGas(balance)
              var left = Context(calls: 0, reply: reply)
              var right = Context(calls: 0, reply: reply)
              let a = baseline(f, memory, info, steps, cycles, permitted, left)
              let b = candidate(f, table, memory, info, steps, cycles, permitted, right)
              same(a, b)
              assert left.calls == right.calls
              if reply == Reply.Continue and cycles == 4096 and balance > 0:
                assert left.calls == int(min(permitted, min(3'u64, (steps + 2) div 6)))
              sameMemory(memory, memoryFor(address, 9, 0))
              inc result
  for increment in [1'u8, 3'u8]:
    # Different program owners have identical PCs but distinct immediates; no operands may leak.
    let other = guest(0, true, increment)
    let otherTable = plan(other)
    for seed in [0'u64, 123'u64, high(uint64) - 1]:
      for address in [0x10000'u64, 0x10ffc'u64]:
        let memory = memoryFor(address, seed, 0)
        let info = infoFor(other, address, 3)
        var context = Context(calls: 0, reply: Reply.Continue)
        let observed = candidate(other, otherTable, memory, info, 19, 4096, 3, context)
        complete(other, observed, info, address, seed, 3)
        assert context.calls == 3
        sameMemory(memory, memoryFor(address, seed, 0))
        inc result

  for address in [0x10000'u64, 0x10ffc'u64]:
    # Repeated valid host replacements alter subsequent guest loads without changing prepared code.
    let memory = memoryFor(address, 9, 0)
    let info = infoFor(f, address, 3)
    var left = Context(calls: 0, reply: Reply.ReplaceMemory)
    var right = Context(calls: 0, reply: Reply.ReplaceMemory)
    let actual = baseline(f, memory, info, 19, 4096, 3, left)
    same(actual, candidate(f, table, memory, info, 19, 4096, 3, right))
    var expected = info
    expected.pc = CodeAddress(0)
    expected.gas = MachineGas(7)
    expected.blockCharged = true
    expected.registers[6] = RegisterValue(3)
    expected.registers[8] = RegisterValue(78)
    expected.registers[9] = RegisterValue(3)
    assert actual.exit == ord(reference.StepExit.Halt) and left.calls == 3 and right.calls == 3
    sameInfo(actual.info, expected)
    sameMemory(actual.memory, memoryFor(address, 77, 0))
    sameMemory(memory, memoryFor(address, 9, 0))
    inc result
  for isolated in [false, true]:
    # Revisit the first table after other owners, then execute a table whose original owner retired.
    let selected = if isolated: orphanPlan() else: table
    let memory = memoryFor(0x10000, 17, 0)
    let info = infoFor(f, 0x10000, 3)
    var context = Context(calls: 0, reply: Reply.Continue)
    complete(f, candidate(f, selected, memory, info, 19, 4096, 3, context), info, 0x10000, 17, 3)
    assert context.calls == 3
    inc result

proc manualHostChecks(): int =
  ## Observe a suspension directly, apply each trusted response, then resume through the same table.
  result = 0
  let f = guest(0, true, 1)
  let table = plan(f)
  for address in [0x10000'u64, 0x10ffc'u64]:
    let memory = memoryFor(address, 9, 0)
    let info = infoFor(f, address, 1)
    let source = captureMachine(f.owner, memory, info).value
    let a = reference.execute(source, reference.ExecutionStepLimit(7), GasCycleLimit(4096))
    let b = prepared.executeShared(table, memory, info, prepared.ExecutionStepLimit(7),
        GasCycleLimit(4096))
    let suspended = observe(a)
    same(suspended, observe(b))
    assert suspended.exit == ord(reference.StepExit.Host) and suspended.detail == 7
    var expected = info
    expected.pc = CodeAddress(f.hostPc)
    expected.gas = MachineGas(uint64(info.gas) - f.price)
    expected.blockCharged = true
    expected.registers[8] = RegisterValue(10)
    sameInfo(suspended.info, expected)
    sameMemory(suspended.memory, memoryFor(address, 10, 0))
    for reply in [Reply.Continue, Reply.Panic, Reply.OutOfGas, Reply.Halt,
        Reply.Uninitialized, Reply.BadMemory, Reply.Debt, Reply.ReplaceMemory]:
      var left = Context(calls: 0, reply: reply)
      var right = Context(calls: 0, reply: reply)
      let applied = reference.applyHostResponse(a.value, respond(left, a.value))
      let other = prepared.applyHostResponse(b.value, respond(right, b.value))
      let actual = observe(applied)
      same(actual, observe(other))
      assert left.calls == 1 and right.calls == 1
      if reply in [Reply.Continue, Reply.ReplaceMemory]:
        expected.pc = CodeAddress(f.counterPc)
        expected.gas = MachineGas(uint64(info.gas) - f.price - 1)
        expected.registers[6] = RegisterValue(1)
        sameInfo(actual.info, expected)
        let done = baseline(f, actual.memory, actual.info, 3, 4096, 0, left)
        let preparedDone = candidate(f, table, actual.memory, actual.info, 3, 4096, 0, right)
        same(done, preparedDone)
        if reply == Reply.ReplaceMemory:
          # Valid host memory replacement must survive reentry even though the program table is reused.
          var final = info
          final.pc = CodeAddress(0)
          final.gas = MachineGas(7)
          final.blockCharged = true
          final.registers[6] = RegisterValue(1)
          final.registers[8] = RegisterValue(10)
          final.registers[9] = RegisterValue(1)
          sameInfo(done.info, final)
          sameMemory(done.memory, memoryFor(address, 77, 0))
        else:
          complete(f, done, info, address, 9, 1)
      elif reply in [Reply.Panic, Reply.OutOfGas]:
        var terminal = suspended.info
        terminal.gas = MachineGas(uint64(terminal.gas) - 1)
        terminal.registers[6] = RegisterValue(1)
        sameInfo(actual.info, terminal)
        assert actual.exit == ord(if reply == Reply.Panic: reference.StepExit.Panic else: reference.StepExit.OutOfGas)
      else:
        assert actual.error == ord(reference.StepError.InvalidHostResponse)
      sameMemory(memory, memoryFor(address, 9, 0))
      inc result

proc benchmark() =
  ## Measure complete memory/host invocations, including equivalent input-snapshot construction.
  for scenario in 0..<5:
    let hosted = scenario >= 2
    let extra = if scenario == 4: 32 else: 0
    let address = if scenario mod 2 == 1: 0x10ffc'u64 else: 0x10000'u64
    let f = guest(extra, hosted, 1)
    let table = plan(f)
    echo "LAYOUT,", scenario, ",", codeLength(f.owner).value, ",", prepared.preparedBytes(table)
    for loops in [1'u64, 1000'u64]:
      let memory = memoryFor(address, 9, 0)
      let info = infoFor(f, address, loops)
      let steps = loops * uint64(f.attempts) + 1
      let batch = if loops == 1: 100 else: 2
      for sample in 0..<13:
        for order in 0..<3:
          let mode = (sample + order) mod 3
          var observations = newSeq[Observation](batch)
          var calls = 0
          let wallStart = getMonoTime().ticks
          let cpuStart = cpuNanoseconds()
          for i in 0..<batch:
            # Each callback context is invocation-owned; prepared code is reused independently.
            var context = Context(calls: 0, reply: Reply.Continue)
            case mode
            of 0: observations[i] = baseline(f, memory, info, steps, 4096, loops, context)
            of 1: observations[i] = candidate(f, table, memory, info, steps, 4096, loops, context)
            else: observations[i] = candidate(f, plan(f), memory, info, steps, 4096, loops, context)
            calls += context.calls
          let cpuElapsed = cpuNanoseconds() - cpuStart
          let wallElapsed = getMonoTime().ticks - wallStart
          assert calls == (if hosted: int(loops) * batch else: 0)
          for observed in observations: complete(f, observed, info, address, 9, loops)
          sameMemory(memory, memoryFor(address, 9, 0))
          if sample >= 3:
            echo "EFFECT,", scenario, ",", loops, ",", mode, ",", sample - 3,
              ",", wallElapsed, ",", cpuElapsed, ",", batch

if getEnv("PVM_IR_ASSERT_PROBE") == "1":
  assert false, "pvm-ir effects assertion control"
let checked = preparationChecks() + memoryChecks() + hostChecks() + manualHostChecks()
echo "CHECK,", checked
benchmark()
