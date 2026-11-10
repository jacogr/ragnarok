# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unbound seven-block histories and exact source seals, with separate direct publisher controls.

import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream
import ../../../src/pvm/internal/x86_jit

when not defined(pvmX86Jit):
  assert false, "the default x86 suite needs pvmX86Jit"
when not defined(pvmX86WideParentRefusalWitness):
  assert false, "the x86 suite needs its direct parent-refusal control"

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Encode only the program container; the instruction and branch bytes below are independent literals.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc source(decoyCopies = 0, branchUsesGuardRegister = false): Program =
  ## A real source backedge discovers the seven-block graph. Extra complete narrow
  ## copies give the same owner many unrelated startup candidates before its valid source.
  assert decoyCopies >= 0 and decoyCopies <= 17
  let original = [
    @[131'u8, 0x88, 1], @[149'u8, 0, 1],
    @[81'u8, 0x28, 0x40, 1, 0x3e, 0],
    @[88'u8, (if branchUsesGuardRegister: 0'u8 else: 2'u8), 0xf4],
    @[2'u8], @[57'u8, 2, 0xac, 0x45, 9],
    @[149'u8, 0, 1], @[129'u8, 0x10, 0x60],
    @[149'u8, 0, 1], @[1'u8],
    @[51'u8, 11], @[200'u8, 0x54, 10], @[149'u8, 0xaa, 1], @[1'u8],
    @[198'u8, 0xb6, 9], @[120'u8, 0x49], @[149'u8, 0x44, 1],
    @[149'u8, 0xbb, 8], @[171'u8, 0xa4, 0xf5],
    @[2'u8], @[57'u8, 2, 0xb4, 0x45, 9], @[131'u8, 0x33, 1],
    @[173'u8, 0x23, 0xe0],
    @[40'u8, 0xbe], @[0'u8],
    @[120'u8, 0x49], @[40'u8, 0xc5]]
  var parts: seq[seq[byte]] = @[]
  for part in original: parts.add(part)
  for copy in 0..<decoyCopies:
    # Relative internal edges stay within each narrow copy; its outer edge has no wide guard.
    for index in 10..24: parts.add(original[index])
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for value in part: code.add(value)
  assert starts[0] == 0 and starts[3] == 12 and starts[10] == 31 and
    starts[14] == 40 and starts[19] == 54 and starts[23] == 66
  for copy in 0..<decoyCopies:
    assert starts[27+15*copy] == 73+38*copy
  var wire: seq[byte] = @[]
  appendNatural(wire, 0)
  wire.add(0)
  appendNatural(wire, uint64(code.len))
  for value in code: wire.add(value)
  var bitmap = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    bitmap[start div 8] = bitmap[start div 8] or (1'u8 shl (start mod 8))
  for value in bitmap: wire.add(value)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(65536),
    JumpCountLimit(256))
  assert decoded.error == ProgramError.None
  decoded.value

proc prepared(program: Program, native: bool): FlatPlan =
  ## Both plans own the same immutable source with distinct permissions, without a bound session.
  var outcome = prepareFlatPlan(program, GasCycleLimit(100000),
    defaultFlatLimits(), allowNative = native)
  assert outcome.error == FlatError.None
  takeValue(outcome)

proc infoAt(gas = 100000'u64): MachineInfo =
  ## Distinct source roles and a separate loop bound expose accidental register or alias changes.
  result = MachineInfo(pc: CodeAddress(69), gas: MachineGas(gas),
    registers: default(RegisterFile))
  result.registers[1] = RegisterValue(607564)
  result.registers[2] = RegisterValue(1)
  result.registers[4] = RegisterValue(610304)
  result.registers[5] = RegisterValue(3)
  result.registers[6] = RegisterValue(0x44332211)
  result.registers[10] = RegisterValue(999999)

proc pages(): array[2, PageImage] =
  ## Literal RO/RW pages retain permissions, distinct contents and complete checked memory comparisons.
  result = default(array[2, PageImage])
  result[0] = PageImage(index: PageIndex(148), access: PageAccess.ReadOnly)
  result[1] = PageImage(index: PageIndex(149), access: PageAccess.ReadWrite)
  result[0].bytes[1452] = 2
  result[0].bytes[1460] = 2

proc equalOutcome(actual, checked: FlatFrame) =
  ## Compare every public stop and both complete pages, including a fault's retained paid state.
  assert actual.reason == checked.reason and actual.exit == checked.exit and
    actual.remaining == checked.remaining and actual.info.pc == checked.info.pc and
    actual.info.gas == checked.info.gas and
    actual.info.gasDeficit == checked.info.gasDeficit and
    actual.info.blockCharged == checked.info.blockCharged and
    actual.info.registers == checked.info.registers and
    actual.faultPage == checked.faultPage
  let actualMemory = flatMemorySnapshot(actual)
  let checkedMemory = flatMemorySnapshot(checked)
  for page in [PageIndex(148), PageIndex(149)]:
    let a = pageImage(actualMemory, page)
    let b = pageImage(checkedMemory, page)
    assert a.error == b.error
    if a.error == MachineError.None:
      assert a.value.access == b.value.access and a.value.bytes == b.value.bytes

proc checkUnbound(frame: FlatFrame) =
  ## Ordinary frames have no shared session or old JIT; semantic comparisons prove the guest result.
  assert flatX86Statistics(frame) == default(array[5, uint64]), "unbound frame has no native image or entry"
  assert flatX86WideStatistics(frame) == default(array[2, uint64]), "unbound frame has no wide entry"
  assert flatX86MemoryCycleStatistics(frame) == default(array[2, uint64]), "no dormant child execution"

let sourceProgram = source()
let nativePlan = prepared(sourceProgram, true)
let checkedPlan = prepared(sourceProgram, false)
let initialPages = pages()
var native = newFlatFrame(nativePlan, initialPages, infoAt())

# Repeated unbound calls preserve full checked results without default eager native admission.
runFlat(native, 20000)
replaceFlatMemory(native, initialPages, infoAt())
var checked = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(native, 20000)
runFlat(checked, 20000)
equalOutcome(native, checked)
checkUnbound(native)

# A direct branch may jump straight to the guard, bypassing read, child,
# and outside. One entry exits rare immediately; the other takes a guard
# backedge first. Compare the paid state and entire memory with checked execution.
for start in [319'u64, 318'u64]:
  var directBranch = infoAt()
  directBranch.pc = CodeAddress(12)
  directBranch.registers[2] = RegisterValue(0)
  directBranch.registers[8] = RegisterValue(start)
  replaceFlatMemory(native, initialPages, directBranch)
  var checkedDirectBranch = newFlatFrame(checkedPlan, initialPages, directBranch)
  runFlat(native, 20)
  runFlat(checkedDirectBranch, 20)
  equalOutcome(native, checkedDirectBranch)
  checkUnbound(native)

# A direct guard entry bypasses the source branch but keeps the same
# source result. A quota boundary on the branch backedge also preserves the
# exact charged header through checked reentry.
var directGuard = infoAt()
directGuard.pc = CodeAddress(0)
directGuard.registers[2] = RegisterValue(0)
directGuard.registers[8] = RegisterValue(319)
replaceFlatMemory(native, initialPages, directGuard)
var checkedDirectGuard = newFlatFrame(checkedPlan, initialPages, directGuard)
runFlat(native, 20)
runFlat(checkedDirectGuard, 20)
equalOutcome(native, checkedDirectGuard)
var boundedBranch = infoAt()
boundedBranch.pc = CodeAddress(12)
boundedBranch.registers[2] = RegisterValue(0)
boundedBranch.registers[8] = RegisterValue(318)
replaceFlatMemory(native, initialPages, boundedBranch)
var checkedBoundedBranch = newFlatFrame(checkedPlan, initialPages, boundedBranch)
runFlat(native, 4)
runFlat(checkedBoundedBranch, 4)
equalOutcome(native, checkedBoundedBranch)
checkUnbound(native)

# A regular entry can also reach the direct guard arm through data: zero RO
# words make the read/child path clear R2 before the next outer branch.
var zeroReadPages = pages()
zeroReadPages[0].bytes[1452] = 0
zeroReadPages[0].bytes[1460] = 0
replaceFlatMemory(native, zeroReadPages, infoAt())
var checkedZeroRead = newFlatFrame(checkedPlan, zeroReadPages, infoAt())
runFlat(native, 20000)
runFlat(checkedZeroRead, 20000)
equalOutcome(native, checkedZeroRead)
checkUnbound(native)

# In this admitted source variant the guard increments the register tested by
# the outer branch. One direct guard visit switches the next branch to read;
# a missing RO page then produces a charged read replay after two branch visits.
let aliasProgram = source(branchUsesGuardRegister = true)
let aliasPlan = prepared(aliasProgram, true)
let aliasCheckedPlan = prepared(aliasProgram, false)
var aliasWarm = infoAt()
aliasWarm.registers[0] = RegisterValue(1)
aliasWarm.registers[8] = RegisterValue(0)
var aliasFrame = newFlatFrame(aliasPlan, initialPages, aliasWarm)
runFlat(aliasFrame, 20000)
replaceFlatMemory(aliasFrame, initialPages, aliasWarm)
runFlat(aliasFrame, 20000)
checkUnbound(aliasFrame)
var readRefusal = infoAt()
readRefusal.pc = CodeAddress(12)
readRefusal.registers[0] = RegisterValue(0)
readRefusal.registers[8] = RegisterValue(0)
let noReadPage = @[initialPages[1]]
replaceFlatMemory(aliasFrame, noReadPage, readRefusal)
var checkedReadRefusal = newFlatFrame(aliasCheckedPlan, noReadPage, readRefusal)
runFlat(aliasFrame, 100)
runFlat(checkedReadRefusal, 100)
equalOutcome(aliasFrame, checkedReadRefusal)
assert aliasFrame.exit == StepExit.Fault
checkUnbound(aliasFrame)

when defined(linux) and defined(amd64) and not defined(pvmX86JitRefuse):
  proc directWidePublication(refuseParent: bool) =
    ## The raw publisher owns only code and copied source. The checked frame never gains a native handler.
    let plan = prepared(sourceProgram, true)
    let foreign = prepared(sourceProgram, true)
    var initial = pages()
    for offset in 0..<4096: initial[1].bytes[offset] = 0xa5
    var frame = newFlatFrame(plan, initial, infoAt())
    const Budget = 20000'u64
    runFlat(frame, Budget) # Warm only the checked source edges used by the seal.
    resetFlatFrame(frame, infoAt())
    runFlat(frame, 2) # The checked prelude writes one byte, then jumps to the unpaid Gate.
    assert frame.info.pc == CodeAddress(12) and not frame.info.blockCharged
    let cpu = frame.info
    let snapshot = flatMemorySnapshot(frame)
    let before = memoryImages(snapshot).value
    assert before.len == 2 and before[0] == initial[0] and before[1].bytes != initial[1].bytes
    var candidate = default(X86WideCycleCandidate)
    var emission = default(X86WideEmission)
    assert flatX86WideSourceProof(frame, 31, candidate, emission)
    assert candidate.loopBranch.pc == 12 and candidate.rare.pc == 68
    let owner = newX86Jit()
    let identity = cast[pointer](plan)
    let other = cast[pointer](foreign)
    assert identity != other
    let child = publishX86MemoryCycle(owner, candidate.cycle, emission.prefix, identity)
    assert child >= 0 and owner.fragments == 1 and owner.codeBytes > 0
    assert x86CycleBound(owner, child, identity) and not x86CycleBound(owner, child, other)
    let childBytes = owner.codeBytes
    if refuseParent:
      x86WideRefuseParentOnceWitness(owner)
      assert x86WideParentRefusalPending(owner)
    let installed = publishX86WideCycle(owner, candidate, emission, child, identity)
    assert installed != refuseParent and not x86WideParentRefusalPending(owner)
    checkUnbound(frame)

    # Both descriptors point to private fixture copies. The prelude proved page 149 dirty.
    var ro = before[0]
    var rw = before[1]
    let roStart = uint64(uint32(ro.index))*4096
    let rwStart = uint64(uint32(rw.index))*4096
    var dirty = @[0'u64, 0'u64, 1'u64 shl (149 mod 64)]
    let beforeDirty = dirty
    var memory = X86WideMemory(
      cycle: X86CycleMemory(readPtr: addr ro.bytes[0], readFirst: roStart, readEnd: roStart+4096,
        writePtr: addr rw.bytes[0], writeFirst: rwStart, writeEnd: rwStart+4096,
        dirtyWords: uint32(dirty.len)),
      # The absent stack sorts above the fixture extents, exactly as in the frame.
      regions: [X86WideReadRegion(first: uint64(high(uint32)), ending: uint64(high(uint32))),
        X86WideReadRegion(data: addr rw.bytes[0], first: rwStart, ending: rwStart+4096),
        X86WideReadRegion(data: addr ro.bytes[0], first: roStart, ending: roStart+4096)])
    var registers = cpu.registers
    var state = X86WideState(cycle: X86CycleState(gas: uint64(cpu.gas), attempts: Budget,
      lastCompleted: high(uint32)))
    let untouched = state
    if refuseParent:
      # A source-valid child occupies the arena, but no frame or active parent can enter it.
      assert owner.fragments == 1 and owner.codeBytes == childBytes
      assert not x86WideActive(owner) and not x86WideBound(owner, identity)
      assert callX86WideCycle(owner, registers, memory, dirty, state) == 0
      assert state == untouched and registers == cpu.registers and dirty == beforeDirty
      assert ro == before[0] and rw == before[1]
      assert owner.calls == 0 and x86MemoryCycleStatistics(owner) == default(array[2, uint64])
      var expected = newFlatFrame(checkedPlan, before, cpu)
      runFlat(frame, Budget)
      runFlat(expected, Budget)
      equalOutcome(frame, expected)
    else:
      assert owner.fragments == 2 and owner.codeBytes > childBytes
      assert x86WideBound(owner, identity) and not x86WideBound(owner, other)
      let receipt = callX86WideCycle(owner, registers, memory, dirty, state)
      let next = uint32(receipt and 0xffffffff'u64)
      assert receipt shr 32 == 1 and state.cycle.exitKind == 2 and next == candidate.rare.header,
        "positive parent must return at the genuine rare exit"
      assert flatX86WideReceiptProof(candidate, uint64(cpu.gas), Budget, state, next),
        "positive parent receipt must match original charged source spans"
      assert recordX86WideCycle(owner, candidate, state)
      assert x86WideStatistics(owner)[0] == 1 and x86MemoryCycleStatistics(owner)[0] == 320
      assert state.childCalls == 320 and state.cycle.wordGroups > 0
      assert dirty == beforeDirty and ro == before[0] and rw.bytes != before[1].bytes
      let used = Budget-state.cycle.attempts
      assert used == 12508 and uint64(cpu.gas)-state.cycle.gas == 68956
      var prefix = newFlatFrame(checkedPlan, before, cpu)
      runFlat(prefix, used)
      assert prefix.remaining == 0 and prefix.reason == StepError.StepLimitExceeded
      let afterCpu = MachineInfo(pc: CodeAddress(uint64(candidate.rare.pc)),
        gas: MachineGas(state.cycle.gas), registers: registers)
      assert prefix.info == afterCpu
      assert memoryImages(flatMemorySnapshot(prefix)).value == @[ro, rw]
      var resumed = newFlatFrame(checkedPlan, [ro, rw], afterCpu)
      var expected = newFlatFrame(checkedPlan, before, cpu)
      runFlat(resumed, state.cycle.attempts)
      runFlat(expected, Budget)
      equalOutcome(resumed, expected)
    assert memoryImages(snapshot).value == before
    checkFlatSource(frame, initial)
    checkUnbound(frame)

  directWidePublication(true)
  directWidePublication(false)

# A tail backedge can be cached while the outer guard's other arm remains unprepared.
# Moving the checked stream preserves the partial graph and allows a later source proof.
let pendingPlan = prepared(sourceProgram, true)
var fromPrefix = infoAt()
fromPrefix.pc = CodeAddress(31)
var pending = newFlatFrame(pendingPlan, initialPages, fromPrefix)
runFlat(pending, 30)
var narrowShape = default(X86MemoryCycleCandidate)
var pendingShape = default(X86WideCycleCandidate)
assert pending.reason == StepError.StepLimitExceeded and
  flatX86SealMemoryCycle(pending, 31, narrowShape) and
  not flatX86SealWideCycle(pending, 31, pendingShape)
var pendingStream = takeFlatStream(pending)
var later = newFlatFrame(pendingPlan, initialPages, infoAt())
restoreFlatStream(later, pendingStream)
var laterChecked = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(later, 20000)
runFlat(laterChecked, 20000)
equalOutcome(later, laterChecked)
# No publication patches these handlers; later source preparation now genuinely completes the wide proof.
checkUnbound(later)
assert flatX86SealWideCycle(later, 31, pendingShape)
replaceFlatMemory(later, initialPages, infoAt())
var laterCheckedAgain = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(later, 20000)
runFlat(laterCheckedAgain, 20000)
equalOutcome(later, laterCheckedAgain)
checkUnbound(later)

when defined(pvmX86MemoryCycleSealWitness):
  block staleSourceTarget:
    # An unpaid interior entry captures a suffix; a following paid resume must not authorize the old terminal.
    var frame = newFlatFrame(prepared(sourceProgram, true), initialPages, fromPrefix)
    runFlat(frame, 30)
    var candidate = default(X86MemoryCycleCandidate)
    assert flatX86SealMemoryCycle(frame, 31, candidate), "genuine source candidate before overlap"
    let header = candidate.tail.header
    let oldTerminal = candidate.tail.terminal
    assert flatX86CompleteTargetWitness(frame, header), "genuine original complete tail"
    assert not flatX86CompleteTargetWitness(frame, oldTerminal), "old terminal has no header authority"
    var paid = fromPrefix
    paid.pc = CodeAddress(63)
    paid.blockCharged = false
    resetFlatFrame(frame, paid)
    runFlat(frame, 1)
    var suffix = default(array[5, uint64])
    assert flatSourceIntervalProof(frame, 63, 65, suffix) and suffix[1] == 22 and
      suffix[2] == 22 and suffix[3] == 1, "literal captured branch suffix"
    paid.blockCharged = true
    resetFlatFrame(frame, paid)
    runFlat(frame, 1)
    assert not flatX86CompleteTargetWitness(frame, oldTerminal) and
      not flatX86CompleteTargetWitness(frame, uint32(suffix[0])), "overlapping suffix cannot authorize stale target"
    assert flatX86CompleteTargetWitness(frame, header), "original complete source remains valid"

# Retain every distinct decoy source/backedge and late source outcome.
# Each copied narrow loop still lacks the complete outer wide edge, as its source proof must show.
let crowdedProgram = source(17)
let crowdedPlan = prepared(crowdedProgram, true)
let crowdedCheckedPlan = prepared(crowdedProgram, false)
var crowded = newFlatFrame(crowdedPlan, initialPages, infoAt())
for copy in 0..<17:
  let pc = uint32(73+38*copy)
  var decoyInfo = infoAt()
  decoyInfo.pc = CodeAddress(uint64(pc))
  replaceFlatMemory(crowded, initialPages, decoyInfo)
  var checkedDecoy = newFlatFrame(crowdedCheckedPlan, initialPages, decoyInfo)
  runFlat(crowded, 30)
  runFlat(checkedDecoy, 30)
  equalOutcome(crowded, checkedDecoy)
  var decoyNarrow = default(X86MemoryCycleCandidate)
  var decoyWide = default(X86WideCycleCandidate)
  assert flatX86SealMemoryCycle(crowded, pc, decoyNarrow) and
    not flatX86SealWideCycle(crowded, pc, decoyWide)
replaceFlatMemory(crowded, initialPages, fromPrefix)
runFlat(crowded, 30)
assert flatX86SealMemoryCycle(crowded, 31, narrowShape) and
  not flatX86SealWideCycle(crowded, 31, pendingShape)
replaceFlatMemory(crowded, initialPages, infoAt())
var checkedCrowded = newFlatFrame(crowdedCheckedPlan, initialPages, infoAt())
runFlat(crowded, 20000)
runFlat(checkedCrowded, 20000)
equalOutcome(crowded, checkedCrowded)
replaceFlatMemory(crowded, initialPages, infoAt())
var checkedCrowdedAgain = newFlatFrame(crowdedCheckedPlan, initialPages, infoAt())
runFlat(crowded, 20000)
runFlat(checkedCrowdedAgain, 20000)
equalOutcome(crowded, checkedCrowdedAgain)
checkUnbound(crowded)

# Replacing all memory capabilities preserves source-bound code and exact checked fallback.
for quota in [0'u64, 1, 2, 3, 4, 5, 8, 20, 1000]:
  replaceFlatMemory(native, initialPages, infoAt())
  var expected = newFlatFrame(checkedPlan, initialPages, infoAt())
  runFlat(native, quota)
  runFlat(expected, quota)
  equalOutcome(native, expected)
replaceFlatMemory(native, initialPages, infoAt())
var checkedAfterQuota = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(native, 20000)
runFlat(checkedAfterQuota, 20000)
equalOutcome(native, checkedAfterQuota)
checkUnbound(native)

# Out-of-gas reentry uses the original charge worker at the exact paid boundary.
for gas in [0'u64, 1, 10, 100]:
  let lowGas = infoAt(gas)
  replaceFlatMemory(native, initialPages, lowGas)
  var expected = newFlatFrame(checkedPlan, initialPages, lowGas)
  runFlat(native, 20000)
  runFlat(expected, 20000)
  equalOutcome(native, expected)
replaceFlatMemory(native, initialPages, infoAt())
var checkedAfterGas = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(native, 20000)
runFlat(checkedAfterGas, 20000)
equalOutcome(native, checkedAfterGas)
checkUnbound(native)

# A missing RO read page retains the canonical checked fault; native memory borrowing is unported.
let missingRead = @[initialPages[1]]
replaceFlatMemory(native, missingRead, infoAt())
var checkedFault = newFlatFrame(checkedPlan, missingRead, infoAt())
runFlat(native, 20000)
runFlat(checkedFault, 20000)
equalOutcome(native, checkedFault)
assert native.exit == StepExit.Fault
replaceFlatMemory(native, initialPages, infoAt())
var checkedAfterFault = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(native, 20000)
runFlat(checkedAfterFault, 20000)
equalOutcome(native, checkedAfterFault)
checkUnbound(native)

# The exact plan may lease its active stream after a fault recovery; a different plan cannot take it.
var stream = takeFlatStream(native)
var foreign = newFlatFrame(prepared(sourceProgram, true), initialPages, infoAt())
restoreFlatStream(foreign, stream)
runFlat(foreign, 10)
assert foreign.reason == StepError.InvalidPreparedProgram
var restored = newFlatFrame(nativePlan, initialPages, infoAt())
restoreFlatStream(restored, stream)
var checkedRestored = newFlatFrame(checkedPlan, initialPages, infoAt())
runFlat(restored, 20000)
runFlat(checkedRestored, 20000)
equalOutcome(restored, checkedRestored)
checkUnbound(restored)

echo "X86_WIDE_DEFAULT_OK"
