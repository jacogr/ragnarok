# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## GP 0.8.0 checked handler-stream execution with invocation-owned regions and bounded preparation.
## Public immutable snapshot and host adapters live in pvm/step; see spec/pvm-execution.md.
import std/[algorithm, assertions]
when defined(pvmArmMixedGroupReceipt):
  import std/syncio
import ../[program, machine]
import ../gas/[gas, plan as gas_plan, memo as gas_memo]
import ./execution_types as oracle
import ./register_ops
import ./native_pipeline
when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  import ./[arm64_jit, jit_rules]
when defined(pvmX86Jit):
  import ./x86_jit

when NativeCheckedReadEnabled:
  const ReadProbeSlots = 4 ## Fixed call-local candidate capacity.
  type
    ReadProbeCandidate = object ## Exact sealed terminal and its invocation-local evidence.
      pc, header, terminal, sourceFacts: uint32
      operations: int
      eligible: uint64
      resolved: bool
    ReadProbeState = object ## Scalar-only state carried across validated memory replacements.
      candidates: array[ReadProbeSlots, ReadProbeCandidate]
      count, inspected: int
      epoch, segmentBudget: uint64
      observing: bool

type
  FlatFactLimit* = distinct uint64 ## Caller-selected decoded-fact admission policy, separate from guest gas.
  FlatNodeLimit* = distinct uint64 ## Ceiling on emitted header/operation nodes in one exclusive frame.
  FlatPreparationLimit* = distinct uint64 ## Total source span admitted for suffix emission plus containing-block pricing.
  FlatLimits* = object ## Copied local policies; later caller changes cannot change an admitted plan.
    codeBytes*: ProgramByteLimit
    facts*: FlatFactLimit
    jumps*: JumpCountLimit
    pages*: PageLimit
    nodes*: FlatNodeLimit
    preparation*: FlatPreparationLimit
  FlatError* {.pure.} = enum ## Local preparation refusals never masquerade as successful guest exits.
    Uninitialized, None, InvalidPolicy, InvalidProgram, CodeLimitExceeded,
    FactLimitExceeded, JumpLimitExceeded, PageLimitExceeded, StreamLimitExceeded,
      PreparationLimitExceeded, InvalidMemory
  FlatResult*[T] = object ## Private alternatives publish only completely admitted owners.
    case status: FlatError
    of None: completed: T
    else: discard
  FlatArgs = object ## Exactly sixteen bytes: full immediate, secondary low word and genuine sealed register coordinates.
    x: uint64
    y: uint32
    slots: RegisterSlots
  FlatHandler = proc(f: var FlatFrame, off: uint32): uint32 {.nimcall, raises: [].}
  FlatFact = object ## Decoded/priced boundary outside execution, captured from the independently validated program owner.
    args: FlatArgs
    handler: nil FlatHandler
    pc, next, sourceCount, priceIndex, nodeCount: uint32
    opcode: byte
    ending, fallthrough: bool
  FlatSourceInterval = object ## Bounded source coordinates and a captured charge, without complete-header authority.
    first, last, span: uint32
    price: uint64
  FlatMixedOp = object ## Cold source event; each destination write is retained independently.
    memory, store, writes: bool
    base, destination: uint32
    displacement, width: uint32
  FlatMixedGroup = object ## One stable base and one pointer lane absent from the entire guest body.
    writable: bool
    first, minDisp, maxEnd, lane: uint32
  FlatTarget = object ## Only genuine jump-table and block-membership validation supplies positive target facts.
    pc: uint32
    valid: bool
  FlatPlan* = ref object ## One immutable source/fact owner; executable stream mutation belongs only to a frame.
    source: Program
    facts: seq[FlatFact]
    factAt: seq[int]
    pricePcs: seq[CodeAddress]
    cycles: GasCycleLimit
    jumps: seq[FlatTarget]
    limits: FlatLimits # Cold admission policy follows the existing hot plan fields.
    allowNative: bool  # Immutable cold policy; forced interpretation never creates native handlers.
    singleStep: bool   # A bounded adapter plan owns one instruction and never enters whole-program emission.
  FlatRegion = ref object ## Additional fragmented regions retain private bytes and immutable access metadata.
    first: uint64
    access: PageAccess
    bytes: seq[byte]
  FlatMemoryScratch* = ref object
    ## One exclusive idle byte lease; immutable baseline and dirty ordinals restore each new input completely.
    baseline: Memory
    pages: seq[PageDescription]
    roBase, rwBase, stackBase: uint64
    ro, rw, stack: seq[byte]
    extra: seq[FlatRegion]
    dirty: seq[uint32]
    dirtyPages: seq[uint64] # Bounded 128 KiB bitmap; its set bits match dirty exactly.
    payloadBytes: uint64    # Logical baseline and private payload charged to the idle retention limit.
  FlatX86WideProbe = object ## One source PC awaiting complete positive cached targets.
    pc: uint32
    attempts: uint8
  FlatX86WideAdmission = object ## Bounded owner-local cold work, moved with its handlers and JIT.
    count: uint8
    probes: array[16, FlatX86WideProbe]
    seen: seq[byte]             # One lazy bit per source byte prevents repeat enrollment after refusal.
  FlatFrame* = object ## One exclusive active execution; CPU, budgets, callbacks and borrowed native descriptors start afresh.
    plan: FlatPlan
    info*: MachineInfo
    reason*: oracle.StepError
    exit*: oracle.StepExit
    faultPage*: PageAddress
    hostCall*: oracle.HostCallId
    handlers: seq[FlatHandler]
    arguments: seq[FlatArgs]
    sites: seq[uint32]
    compiledForPc: seq[uint32]
    sourceMemory: Memory
    sourcePages: seq[PageDescription]
    roBase, rwBase, stackBase: uint64
    ro, rw, stack: seq[byte]
    extra: seq[FlatRegion]
    remaining*: uint64
    reservation: uint32 # Raw source end, or a high-bit-tagged stable header resolved only on attempted exit.
    stoppedAt: uint32
    attemptedExit: bool
    barrier: uint32
    barrierFact: uint32
    savedHandler: nil FlatHandler
    dynamicOffsets: array[256, uint64] # Full positive ordinal tag plus stable offset; no invocation state is retained.
    hostSnapshot: Memory
    hostReady: bool
    hostSnapshotPc: CodeAddress
    fastResumes, fallbackResumes, hostCopiedPages: uint64
    dirtyPages: seq[uint64]       # One bounded 128 KiB bitmap covers all 32-bit guest pages.
    dirtyIndices: seq[uint32] # Unique written pages; capacity is admitted with the mapping, never grown by a store.
    preparationFailure: FlatError # Rare admission state leaves all existing hot-frame coordinates unchanged.
    preparationUsed: uint64 # Cold source-span reservations persist with the emitted cache across resets/reentry.
    pricingPlan: GasPlan          # Optional source-bound immutable prices, selected only during cold emission.
    pricingMemo: GasMemo          # Optional caller-owned bounded price memo, never CPU or paid gas.
    when defined(pvmArm64Jit) and not defined(pvmX86Jit):
      armOriginal: seq[nil FlatHandler] # Original entries restore exact checked fallback on partial source reservations.
      armJit: nil ArmJit # Exclusively leased code cache retains no invocation CPU, memory or callback addresses.
    when defined(pvmX86Jit):
      x86Original: seq[nil FlatHandler] # Exact checked entries survive every partial reservation and native refusal.
      x86Jit: nil X86Jit          # Exclusive code-only owner; never contains an invocation address.
      x86WideAdmission: FlatX86WideAdmission # Source PCs and retry counts persist with the exact code owner.
      x86PreviousHeader, x86PreviousNext: uint32 # Observed invocation-local edges discover only closed pure loops.
      x86PreviousValid: bool
      when defined(pvmX86CheckedStoreReceipt):
        x86CheckedStoreSelections, x86CheckedByteBlocks, x86CheckedWordGroups: uint64
    when NativeCheckedReadEnabled:
      readContext: NativeReadContext
      readContextReady: bool
      readProbe: ReadProbeState
    nativeSession*: NativeSession # Prepared identity only; never passed to the compiler thread.
    nativeOriginal: nil FlatHandler
    nativeEntry: uint32
    nativeInstalledEpoch: uint64
    pricingKind: byte             # Zero dynamic, one complete plan, two lazy memo; no per-op pricing switch.
    when defined(pvmArm64Jit) and not defined(pvmX86Jit):
      armPreviousHeader, armPreviousNext: uint32 # Invocation-local observed pure-block edges, never retained in source caches.
      armPreviousValid: bool
      armMemory: ArmReadContext   # Raw three triplets precede clipped reads; never retained by FlatStream.
      when defined(pvmArmMacroStateTrace):
        armMacroLastState: ArmMacroState # Private receipt compares every ABI word with linked fallback.




when defined(pvmArm64Jit) or defined(pvmX86Jit):
  proc `=copy`*(destination: var FlatFrame, source: FlatFrame) {.error.}
    ## Reject copying an owner that contains exclusive native JIT resources.

  proc `=dup`*(source: FlatFrame): FlatFrame {.error.}
    ## Reject duplication of an owner that contains exclusive native JIT resources.

const flatStop = high(uint32)
 # Source ordinals fit the four-MiB program ceiling; emitted offsets stay below2^31.
 # The disjoint high bit defers a complete reservation's source lookup until an attempted exit.
const flatReservationHeaderFlag = 0x80000000'u32

func defaultFlatLimits*(): FlatLimits =
  ## Compatibility policy is finite; application callers should choose explicit deployment limits.
  FlatLimits(codeBytes: ProgramByteLimit(4194304), facts: FlatFactLimit(4194304),
    jumps: JumpCountLimit(1048576), pages: PageLimit(1048576), nodes: FlatNodeLimit(8388608),
        preparation: FlatPreparationLimit(67108864))

func error*[T](outcome: FlatResult[T]): FlatError =
  ## Inspect a default/refused result without exposing a partial owner.
  outcome.status

proc takeValue*[T](outcome: var FlatResult[T]): T {.inline, requires: outcome.status ==
    FlatError.None.} =
  ## Transfer an admitted owner once without deep-copying frame regions; consumed results lose success authority.
  result = move(outcome.completed)
  outcome = FlatResult[T](status: FlatError.Uninitialized)

func validFlatLimits(limits: FlatLimits): bool =
  ## Representation ceilings are checked before narrowing, indexing or allocating; zero budgets deliberately refuse work.
  uint64(limits.codeBytes) <= 4194304 and uint64(limits.facts) <= 4194304 and
    uint64(limits.jumps) <= 1048576 and uint32(limits.pages) <= 1048576 and
    uint64(limits.nodes) <= 2147483646

func preparationError*(frame: FlatFrame): FlatError =
  ## A stream-admission failure is sticky for this frame; no successful guest snapshot is claimed.
  frame.preparationFailure

func flatPreparationUnits*(frame: FlatFrame): uint64 =
  ## Copied cumulative source-span reservations; these are neither actual decoder visits nor CPU instructions/cycles.
  frame.preparationUsed

func flatSext32(x: uint32): uint64 {.inline.} =
  ## Preserve GP sign extension with unsigned bit operations.
  if (x and 0x80000000'u32) != 0: uint64(x) or 0xffffffff00000000'u64
  else: uint64(x)

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  proc flatArmPrepare(f: var FlatFrame, origin: uint32)
    ## Cold suffix preparation may replace eligible entries with native fragments.

  proc flatArmCycle(f: var FlatFrame, first, middle, last: uint32, destination: var uint32): bool
    ## Only an observed, fully validated closed cycle may authorize a connected native loop.

when defined(pvmX86Jit):
  proc flatX86Prepare(f: var FlatFrame, origin: uint32)
    ## Cold source emission alone can replace complete pure spans with native entries.
  proc flatX86ColdWideAdmission(f: var FlatFrame, tail: uint32)
    ## Record one positive backedge or settle bounded source candidates at a safe call boundary.

proc flatConsiderNative(f: var FlatFrame, origin: uint32)
when NativeCheckedReadEnabled:
  proc discoverReadProbe(f: var FlatFrame, header, pc: uint32)
    ## Classify one bounded candidate without generating any native bytes.

proc flatResolve(f: var FlatFrame, pc: uint32): uint32
  ## Cold lazy stream emission is forward-declared for target patching.

proc flatStopExit(f: var FlatFrame, off: uint32, kind: oracle.StepExit,
    attempted: bool = true): uint32 =
  ## Rare exits materialize the exact source PC; ordinary handlers never publish physical PCs.
  f.exit = kind
  f.stoppedAt = off
  f.attemptedExit = attempted
  let fact = f.plan.facts[int(f.sites[int(off)])]
  f.info.pc = if kind in [oracle.StepExit.Halt, oracle.StepExit.Panic]: CodeAddress(
      0) else: CodeAddress(fact.pc)
  flatStop

proc flatLocal(f: var FlatFrame, off: uint32, error: oracle.StepError): uint32 =
  ## A local refusal selects no successful snapshot; the caller restores any temporary budget barrier.
  f.reason = error
  if error != oracle.StepError.StepLimitExceeded:
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
  f.stoppedAt = off
  f.attemptedExit = false
  flatStop

proc flatBudget(f: var FlatFrame, off: uint32): uint32 =
  ## Only a partial block installs this synthetic barrier; folded no-ops still select their exact source boundary.
  f.info.pc = CodeAddress(f.plan.facts[int(f.barrierFact)].pc)
  flatLocal(f, off, oracle.StepError.StepLimitExceeded)

template flatReserve(f: var FlatFrame, off: uint32) =
  ## Reserve a whole straight-line block once; a partial source budget changes one exclusive frame-owned handler temporarily.
  if f.remaining == 0:
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
    return flatLocal(f, off, oracle.StepError.StepLimitExceeded)
  let a = f.arguments[int(off)]
  if not f.info.blockCharged:
    if uint64(f.info.gas) < a.x: return flatStopExit(f, off, oracle.StepExit.OutOfGas, false)
    f.info.gas = MachineGas(uint64(f.info.gas)-a.x)
    f.info.blockCharged = true
  if f.remaining >= uint64(a.y):
    f.remaining-=uint64(a.y)
    # Whole-block exits are rare: retain its stable header instead of reading the source index on every entry.
    # Emitted offsets are below2^31; raw source ends are at most the four-MiB fact ceiling.
    f.reservation = off or flatReservationHeaderFlag
  else:
    let reserved = f.remaining
    f.remaining = 0
    f.reservation = f.sites[int(off)]+uint32(reserved)
    f.barrierFact = f.reservation
    # Multiple cached suffixes can represent this same source PC. Patch only the active stream,
    # whose sites are ordered; a folded no-op stops at the next real node but reports its own PC.
    var boundary = off+1
    while int(boundary) < f.sites.len and f.sites[int(boundary)] < f.barrierFact:
      inc boundary
    assert int(boundary) < f.handlers.len
    assert uint64(f.sites[int(boundary)]) < uint64(f.sites[int(off)])+uint64(a.y)
    f.barrier = boundary
    f.savedHandler = f.handlers[int(f.barrier)]
    f.handlers[int(f.barrier)] = flatBudget

proc flatReserveHeader(f: var FlatFrame, off: uint32): uint32 {.alwaysInline.} =
  ## The dispatch loop reserves ordinary headers with the exact shared checks, then selects the patched body.
  flatReserve(f, off)
  off+1

proc flatCharge(f: var FlatFrame, off: uint32): uint32 =
  ## Ordinary headers retain their original indirect handoff after the shared complete reservation checks.
  flatReserve(f, off)
  # A successful entry consumes the next already sealed handler immediately; at most the existing
  # disjoint operation prefix adds a third call. Control transfers return offsets, never recurse.
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

proc flatChargeFailure[Error: static[oracle.StepError]](f: var FlatFrame, off: uint32): uint32 =
  ## Preserve attempt-limit precedence and allow already-paid blocks past unused price failures.
  if f.remaining == 0:
    # Source-attempt exhaustion wins before a failed unused price on a newly reached header.
    f.info.pc = CodeAddress(f.plan.facts[int(f.sites[int(off)])].pc)
    return flatLocal(f, off, oracle.StepError.StepLimitExceeded)

  ## An already-paid resumed block may execute despite a failed unused pricing computation.
  if not f.info.blockCharged: return flatLocal(f, off, Error)
  flatCharge(f, off)

proc flatRegister[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## This is our literal prepared-register worker on a sixteen-byte operand record and flat register file.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  off+1

proc flatRegisterPair[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Master-style register-first prefix: the first mutation completes before the original checked second handler.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

proc flatFusedRegisters[First, Second: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Execute two independently decoded register workers without a second indirect call; the original second node remains addressable.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(First), f.info.registers, index, value, First):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  # A partial reservation still observes the original second-instruction boundary before reading or mutating its operands.
  if f.barrier == next: return flatBudget(f, next)
  let b = f.arguments[int(next)]
  if not computeRegisterOperands(b.slots, b.x, byte(Second), f.info.registers, index, value, Second):
    return flatLocal(f, next, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  next+1

func signedLess(a, b: uint64): bool =
  ## Compare unsigned register bits in signed order by flipping their sign bits.
  (a xor 0x8000000000000000'u64) < (b xor 0x8000000000000000'u64)

# Evaluate the condition against the original register file; decoding already saturated register IDs.
template branchConditionValue(indices: RegisterSlots, immediate: uint64, runtimeOpcode: byte,
    registers: RegisterFile, selectedOpcode: static[int]): bool =
  ## One shared comparison table expands into callers that need no out-of-line branch worker.
  block:
    let a = uint64(registers[indices.aIndex])
    let b = (if runtimeOpcode <= 90: immediate
      else: uint64(registers[indices.bIndex]))
    # Prepared handlers fix the comparison once; ordinary execution keeps its owned runtime opcode.
    let opcode = when selectedOpcode >= 0: byte(selectedOpcode) else: runtimeOpcode
    case opcode
    of 81, 170:
      # Equality has identical signed and unsigned interpretations.
      a == b
    of 82, 171:
      # Inequality also compares raw register bit patterns.
      a != b
    of 83, 172:
      # Unsigned strict lower bound.
      a < b
    of 84:
      # Unsigned inclusive lower bound.
      a <= b
    of 85, 174:
      # Unsigned inclusive upper bound.
      a >= b
    of 86:
      # Unsigned strict upper bound.
      a > b
    of 87, 173:
      # Signed strict lower bound.
      signedLess(a, b)
    of 88:
      # Signed inclusive lower bound.
      not signedLess(b, a)
    of 89, 175:
      # Signed inclusive upper bound.
      not signedLess(a, b)
    else:
      # The only remaining conditional opcode is signed greater-than immediate (90).
      signedLess(b, a)

func branchConditionOperands[SelectedOpcode: static[int]](indices: RegisterSlots,
    immediate: uint64, runtimeOpcode: byte, registers: RegisterFile): bool =
  ## Existing selected comparison workers retain the same shared original-register equation.
  branchConditionValue(indices, immediate, runtimeOpcode, registers, SelectedOpcode)

template flatBranchSelect(f: var FlatFrame, args: FlatArgs, Code: static[int],
    destination: var uint32) =
  ## Cached branch selection changes paid state only after preceding operations and uses copied sealed arms.
  block:
    f.info.blockCharged = false
    destination = if branchConditionValue(args.slots, flatSext32(uint32(args.x and 0xffffffff'u64)),
        byte(Code), f.info.registers, Code): uint32(args.x shr 32)
      else: args.y

proc flatRead[W: static[int]](bytes: seq[byte], at: int): uint64 {.inline.} =
  ## Complete bounds precede reads; the private initialized word never aliases the immutable source span.
  assert at >= 0 and bytes.len >= W and at <= bytes.len-W
  result = 0
  when W == 1:
    # Preserve the original byte worker; only wider selected reads use the transferred primitive.
    for i in 0..<W: result = result or (uint64(bytes[at+i]) shl(8*i))
  else:
    # Match master's little-endian, unaligned-safe scalar load after the unchanged region/permission checks.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      copyMem(addr result, unsafeAddr bytes[at], W)
    else:
      # Other host byte orders retain the original zero-extended little-endian byte equation.
      for i in 0..<W: result = result or (uint64(bytes[at+i]) shl(8*i))

proc flatWrite[W: static[int]](bytes: var seq[byte], at: int, value: uint64) {.inline.} =
  ## No bytes change until the complete selected region extent has passed.
  assert at >= 0 and bytes.len >= W and at <= bytes.len-W
  when W == 1:
    # Preserve the original byte worker literally; the transfer targets only multi-byte stores.
    for i in 0..<W: bytes[at+i] = byte((value shr (8*i)) and 255'u64)
  else:
    # Match master's endian-tested primitive: only admitted bytes copy from a disjoint initialized stack word.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      var word = value
      copyMem(addr bytes[at], addr word, W)
    else:
      # Other host byte orders retain the original portable little-endian equation.
      for i in 0..<W: bytes[at+i] = byte((value shr (8*i)) and 255'u64)

proc flatRememberPage(f: var FlatFrame, page: int) {.noinline.} =
  ## A first write records one admitted page; keep sequence bookkeeping outside repeated-store code.
  assert f.dirtyIndices.len < f.sourcePages.len
  f.dirtyIndices.add(uint32(page))
  let word = page shr 6
  assert word < f.dirtyPages.len
  f.dirtyPages[word] = f.dirtyPages[word] or (1'u64 shl (page and 63))

proc flatMarkStore[W: static[int]](f: var FlatFrame, address: uint64) {.alwaysInline.} =
  ## Mark only after complete store preflight; no allocation or guest-visible state changes occur here.
  assert address <= uint64(high(uint32))-uint64(W-1)
  let first = int(address shr 12)
  let word = first shr 6
  assert word < f.dirtyPages.len
  let mask = 1'u64 shl (first and 63)
  let before = f.dirtyPages[word]
  if (before and mask) == 0:
    # A dirty epoch needs one bit transition per page, even when the guest rewrites it repeatedly.
    flatRememberPage(f, first)
  when W > 1:
    # A scalar can span at most two pages; rejected cross-page stores never reach this helper.
    let last = int((address+uint64(W-1)) shr 12)
    if last != first:
      let lastWord = last shr 6
      assert lastWord < f.dirtyPages.len
      let lastMask = 1'u64 shl (last and 63)
      let lastBefore = f.dirtyPages[lastWord]
      if (lastBefore and lastMask) == 0:
        # The checked scalar may touch a second page in the same bitmap word or the following word.
        flatRememberPage(f, last)

proc flatClearDirty(f: var FlatFrame) =
  ## A successful host checkpoint or input reset makes private bytes equal their immutable base again.
  for page in f.dirtyIndices:
    # Several pages can share a word; repeated clearing is harmless and bounded by written pages.
    f.dirtyPages[int(page shr 6)] = 0
  f.dirtyIndices.setLen(0)

func flatDirty(f: FlatFrame, index: PageIndex): bool {.inline.} =
  ## Captured maps contain only 32-bit-addressable pages; unknown bitmap shapes retain full publication.
  let page = uint64(uint32(index))
  let word = page shr 6
  if word >= uint64(f.dirtyPages.len): return true
  (f.dirtyPages[int(word)] and (1'u64 shl int(page and 63))) != 0

proc flatByte(f: FlatFrame, address: uint64): byte =
  ## Slow paths and observers find the latest private byte only after complete genuine scalar preflight.
  if address >= f.stackBase and address-f.stackBase < uint64(f.stack.len): return f.stack[int(
      address-f.stackBase)]
  if address >= f.rwBase and address-f.rwBase < uint64(f.rw.len): return f.rw[int(address-f.rwBase)]
  if address >= f.roBase and address-f.roBase < uint64(f.ro.len): return f.ro[int(address-f.roBase)]
  for i in 0..<f.extra.len:
    let r {.cursor.} = f.extra[i]
    if address >= r.first and address-r.first < uint64(r.bytes.len): return r.bytes[int(
        address-r.first)]
  assert false, "validated readable byte must belong to a captured private region"
  0

proc flatSetByte(f: var FlatFrame, address: uint64, value: byte) =
  ## Complete store preflight establishes writability across all involved regions before this helper mutates one byte.
  if address >= f.stackBase and address-f.stackBase < uint64(f.stack.len): f.stack[int(
      address-f.stackBase)] = value; return
  if address >= f.rwBase and address-f.rwBase < uint64(f.rw.len): f.rw[int(
      address-f.rwBase)] = value; return
  for i in 0..<f.extra.len:
    let r {.cursor.} = f.extra[i]
    if r.access == PageAccess.ReadWrite and address >= r.first and address-r.first < uint64(r.bytes.len):
      r.bytes[int(address-r.first)] = value
      return
  assert false, "validated writable byte must belong to a captured writable region"

proc flatLoadSlow[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool =
  ## The original immutable memory preflight preserves every protected/overflow/permission/fault ordering; its old byte value is not used.
  let checked = load(f.sourceMemory, MemoryAddress(address), AccessWidth(byte(W)))
  if checked.error != MachineError.None:
    if checked.error == MachineError.Fault:
      f.faultPage = checked.faultPage
      discard flatStopExit(f, off, oracle.StepExit.Fault)
    elif checked.error == MachineError.Panic: discard flatStopExit(f, off, oracle.StepExit.Panic)
    elif checked.error == MachineError.AmbiguousAccessOrder: discard flatLocal(f, off,
        oracle.StepError.AmbiguousAccessOrder)
    else: discard flatLocal(f, off, oracle.StepError.InvalidMachine)
    return false
  value = 0
  for i in 0..<W: value = value or (uint64(flatByte(f, address+uint64(i))) shl (8*i))
  true

proc flatStoreSlow[W: static[int]](f: var FlatFrame, off: uint32, address, value: uint64): bool =
  ## Exact read-only scalar preflight precedes dirty marking and every private byte mutation.
  let checked = writableScalar(f.sourceMemory, MemoryAddress(address), AccessWidth(byte(W)))
  if checked.error != MachineError.None:
    if checked.error == MachineError.Fault:
      f.faultPage = checked.faultPage
      discard flatStopExit(f, off, oracle.StepExit.Fault)
    elif checked.error == MachineError.Panic: discard flatStopExit(f, off, oracle.StepExit.Panic)
    elif checked.error == MachineError.AmbiguousAccessOrder: discard flatLocal(f, off,
        oracle.StepError.AmbiguousAccessOrder)
    else: discard flatLocal(f, off, oracle.StepError.InvalidMachine)
    return false
  flatMarkStore[W](f, address)
  for i in 0..<W: flatSetByte(f, address+uint64(i), byte((value shr (8*i)) and 255'u64))
  true

proc flatLoadFast[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool {.inline.} =
  ## Three-region fast selection keeps only address-dependent complete-extent checks on success.
  if address >= 65536'u64 and address <= uint64(high(uint32))-uint64(W):
    if address >= f.stackBase:
      let at = int(address-f.stackBase)
      if f.stack.len >= W and at <= f.stack.len-W: value = flatRead[W](f.stack, at); return true
    elif address >= f.rwBase:
      let at = int(address-f.rwBase)
      if f.rw.len >= W and at <= f.rw.len-W: value = flatRead[W](f.rw, at); return true
    elif address >= f.roBase:
      let at = int(address-f.roBase)
      if f.ro.len >= W and at <= f.ro.len-W: value = flatRead[W](f.ro, at); return true
  false

proc flatLoad[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
    value: var uint64): bool {.inline.} =
  ## Complete checked fallback remains available to existing source workers.
  if flatLoadFast[W](f, off, address, value): return true
  flatLoadSlow[W](f, off, address, value)

proc flatStore[W: static[int]](f: var FlatFrame, off: uint32, address,
    value: uint64): bool {.alwaysInline.} =
  ## Only captured writable/stack regions can satisfy a fast store; RO and fragmented boundaries retain full preflight.
  if address >= 65536'u64 and address <= uint64(high(uint32))-uint64(W):
    if address >= f.stackBase:
      let at = int(address-f.stackBase)
      if f.stack.len >= W and at <= f.stack.len-W:
        flatWrite[W](f.stack, at, value)
        flatMarkStore[W](f, address)
        return true
    elif address >= f.rwBase:
      let at = int(address-f.rwBase)
      if f.rw.len >= W and at <= f.rw.len-W:
        flatWrite[W](f.rw, at, value)
        flatMarkStore[W](f, address)
        return true
  flatStoreSlow[W](f, off, address, value)

proc flatMemoryCold[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 {.noinline.}
  ## Keep only complete fallback outside hot workers; direct store callers remain eligible for inlining.

proc flatMemoryWorker[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Fast, Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 =
  ## Shared selected access equation; only the cold load worker preserves state across full preflight.
  let a = f.arguments[int(off)]
  var base = 0'u64
  when Indirect:
    when Loading or not ImmediateStore: base = uint64(f.info.registers[a.slots.bIndex])
    else: base = uint64(f.info.registers[a.slots.aIndex])
  let address = (base+a.x) and 0xffffffff'u64
  when Loading:
    var value = 0'u64
    when Fast:
      if not flatLoadFast[Width](f, off, address, value):
        # Failed fast preflight has changed no CPU, bytes or attempt state; the complete worker owns every exit.
        return flatMemoryCold[Width, Loading, Signed, Indirect, ImmediateStore, Pair](f, off)
    else:
      if not flatLoad[Width](f, off, address, value): return flatStop
    when Signed:
      let bits = Width*8
      if (value and (1'u64 shl (bits-1))) != 0: value = value or (high(uint64) shl bits)
    f.info.registers[a.slots.aIndex] = RegisterValue(value)
  else:
    let value = when ImmediateStore: flatSext32(a.y) else: uint64(f.info.registers[a.slots.aIndex])
    if not flatStore[Width](f, off, address, value): return flatStop
  when Pair:
    # Source continuation is unchanged, including partial-budget barriers installed in the next slot.
    let next = off+1
    let selected = f.handlers[int(next)]
    selected(f, next)
  else:
    off+1

proc flatMemoryCold[Width: static[int]; Loading, Signed, Indirect, ImmediateStore,
    Pair: static[bool]](f: var FlatFrame, off: uint32): uint32 {.noinline.} =
  ## One full checked implementation preserves successful fragmented loads and exact terminal state.
  flatMemoryWorker[Width, Loading, Signed, Indirect, ImmediateStore, false, Pair](f, off)

proc flatCachedJump[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Self-patched static nodes retain scalar executable offsets; load-and-jump writes before every exit.
  let a = f.arguments[int(off)]
  when Code == 80: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  f.info.blockCharged = false
  a.y

proc flatResolutionFailure(f: var FlatFrame, off: uint32): uint32 =
  ## Invalid guest destinations panic; local policy exhaustion has no successful guest outcome.
  if f.preparationFailure != FlatError.None: return flatLocal(f, off,
      oracle.StepError.InvalidPreparedProgram)
  flatStopExit(f, off, oracle.StepExit.Panic)

proc flatJump[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Resolve a source-owned sealed static target once and patch only this frame's private stream.
  let a = f.arguments[int(off)]
  when Code == 80: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  let target = flatResolve(f, a.y)
  if target == flatStop: return flatResolutionFailure(f, off)
  f.arguments[int(off)].y = target
  let patched: FlatHandler = flatCachedJump[Code]
  f.handlers[int(off)] = patched
  f.info.blockCharged = false
  target

proc flatBranch[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Conditions use our original-register comparison table; cached arms are already genuine executable offsets.
  let a = f.arguments[int(off)]
  var destination = flatStop
  flatBranchSelect(f, a, Code, destination)
  destination

proc flatUnresolvedBranch[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Prepare both valid arms: resolve both valid arms, patch, then retry this synthetic preparation dispatch without a source attempt.
  let a = f.arguments[int(off)]
  let yes = flatResolve(f, uint32(a.x shr 32))
  let no = flatResolve(f, a.y)
  if yes == flatStop or no == flatStop: return flatResolutionFailure(f, off)
  f.arguments[int(off)].x = (a.x and 0xffffffff'u64) or (uint64(yes) shl 32)
  f.arguments[int(off)].y = no
  let patched: FlatHandler = flatBranch[Code]
  f.handlers[int(off)] = patched
  when defined(pvmX86Jit) and not defined(pvmX86WideManualProof):
    # The original cached branch clears paid state before cold source admission.
    let destination = flatBranch[Code](f, off)
    when Code == 173: flatX86ColdWideAdmission(f, off)
    destination
  else:
    off

proc flatFusedRegisterBranch[First, Branch: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Combine only a validated cached branch with its preceding arithmetic; both source nodes remain addressable.
  let a = f.arguments[int(off)]
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterOperands(a.slots, a.x, byte(First), f.info.registers, index, value, First):
    return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
  f.info.registers[index] = value
  let next = off+1
  # The second source boundary must still stop before reading its operands or clearing the paid flag.
  if f.barrier == next: return flatBudget(f, next)
  let b = f.arguments[int(next)]
  f.info.blockCharged = false
  if branchConditionOperands[Branch](b.slots, flatSext32(uint32(b.x and 0xffffffff'u64)),
      byte(Branch), f.info.registers): uint32(b.x shr 32)
  else: b.y

proc flatRegisterBranchCold[First, Branch: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Original execution validates both branch arms after arithmetic; only a genuine cached branch enables fusion.
  let outcome = flatRegisterPair[First](f, off)
  let cached: FlatHandler = flatBranch[Branch]
  if f.handlers[int(off+1)] == cached:
    # Stable stream offsets survive target preparation and future resets; temporary budget handlers never qualify.
    let combined: FlatHandler = flatFusedRegisterBranch[First, Branch]
    f.handlers[int(off)] = combined
  outcome

template flatShapeRegister(f: var FlatFrame, off: uint32, Code: static[int]) =
  ## Expand the shared register equation inside a charged shape, without an out-of-line composed worker call.
  block:
    let a = f.arguments[int(off)]
    var index: range[0..12] = 0
    var value = RegisterValue(0)
    if not computeRegisterOperands(a.slots, a.x, byte(Code), f.info.registers, index, value, Code):
      return flatLocal(f, off, oracle.StepError.UnsupportedInstruction)
    f.info.registers[index] = value

template flatChargedStep(f: var FlatFrame, off: uint32, First, Second, Branch: static[int],
    destination: var uint32) =
  ## Execute one complete charged shape; failures and partial quotas return immediately from the containing interpreter loop.
  block:
    flatReserve(f, off)
    if f.barrier != flatStop:
      # Partial source quotas use the original addressable nodes and exact temporary boundary handler.
      let selected = f.handlers[int(off+1)]
      return selected(f, off+1)
    flatShapeRegister(f, off+1, First)
    when Second >= 0:
      # A full reservation permits the second original arithmetic operation; partial cases returned through ordinary nodes above.
      flatShapeRegister(f, off+2, Second)
    let branchOff = off+(when Second >= 0: 3'u32 else: 2'u32)
    let args = f.arguments[int(branchOff)]
    flatBranchSelect(f, args, Branch, destination)

proc flatChargedShape[First, Second, Branch: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Follow only exact positive cached shape links in a nonrecursive cycle; arbitrary exits return to ordinary dispatch.
  var current = off
  var destination = flatStop
  var middleOff = flatStop
  var lastOff = flatStop
  # Every logical block still performs its own complete gas and source-budget reservation.
  flatChargedStep(f, current, First, Second, Branch, destination)
  when First == 131:
    let middle: FlatHandler = flatChargedShape[151, 152, 173]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 151, 152, 173, destination)
    let last: FlatHandler = flatChargedShape[200, 139, 82]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 200, 139, 82, destination)
  elif First == 200:
    let middle: FlatHandler = flatChargedShape[131, -1, 88]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 131, -1, 88, destination)
    let last: FlatHandler = flatChargedShape[151, 152, 173]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 151, 152, 173, destination)
  else:
    let middle: FlatHandler = flatChargedShape[200, 139, 82]
    if f.handlers[int(destination)] != middle: return destination
    middleOff = destination
    current = middleOff
    flatChargedStep(f, current, 200, 139, 82, destination)
    let last: FlatHandler = flatChargedShape[131, -1, 88]
    if f.handlers[int(destination)] != last: return destination
    lastOff = destination
    current = lastOff
    flatChargedStep(f, current, 131, -1, 88, destination)
  # Only an actual closed round enables stable coordinates; a same-shaped but different record returns to normal dispatch.
  if destination != off: return destination
  let fixedMiddle = middleOff
  let fixedLast = lastOff
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # Keep the original first closed round; connected code may run only after all three real branch capabilities exist.
    if flatArmCycle(f, off, fixedMiddle, fixedLast, destination): return destination
  while true:
    # Each block retains its charge/quota check. Any changed branch outcome exits before using a different record's operands.
    flatChargedStep(f, off, First, Second, Branch, destination)
    if destination != fixedMiddle: return destination
    when First == 131:
      flatChargedStep(f, fixedMiddle, 151, 152, 173, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 200, 139, 82, destination)
    elif First == 200:
      flatChargedStep(f, fixedMiddle, 131, -1, 88, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 151, 152, 173, destination)
    else:
      flatChargedStep(f, fixedMiddle, 200, 139, 82, destination)
      if destination != fixedLast: return destination
      flatChargedStep(f, fixedLast, 131, -1, 88, destination)
    if destination != off: return destination

proc flatChargedShapeCold[First, Second, Branch: static[int]](f: var FlatFrame,
    off: uint32): uint32 =
  ## Preserve original first-use dispatch until the real terminal branch has validated and cached both arms.
  flatReserve(f, off)
  let selected = f.handlers[int(off+1)]
  let outcome = selected(f, off+1)
  let branchOff = off+(when Second >= 0: 3'u32 else: 2'u32)
  let cached: FlatHandler = flatBranch[Branch]
  if f.handlers[int(branchOff)] == cached:
    # Only positive cached capability enables a whole-block worker; no invalid or temporary handler qualifies.
    let combined: FlatHandler = flatChargedShape[First, Second, Branch]
    f.handlers[int(off)] = combined
  outcome

proc flatChargedStoreLoop(f: var FlatFrame, off: uint32): uint32 =
  ## Keep this complete checked block resident while its genuine cached branch selects the same header.
  while true:
    # Every backedge retains its own complete gas and source-attempt reservation.
    flatReserve(f, off)
    if f.barrier != flatStop:
      # Partial budgets execute the original addressable prefix and its temporary barrier.
      let selected = f.handlers[int(off+1)]
      return selected(f, off+1)
    flatShapeRegister(f, off+1, 198)
    let stored = flatMemoryWorker[1, false, false, true, false, true, false](f, off+2)
    if stored == flatStop:
      # The original store retains prefix mutations, fault PC and the unattempted-reservation refund.
      return stored
    flatShapeRegister(f, off+3, 149)
    flatShapeRegister(f, off+4, 149)
    let args = f.arguments[int(off+5)]
    var destination = flatStop
    flatBranchSelect(f, args, 171, destination)
    when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
      inc f.x86CheckedByteBlocks
    if destination != off:
      # Changed branch outcomes return their real cached target to ordinary dispatch.
      return destination

func flatWordShape(f: FlatFrame, off: uint32): bool =
  ## Bind one byte extraction/store loop to five distinct source roles before selecting its word worker.
  let prefix = f.arguments[int(off+1)]
  let store = f.arguments[int(off+2)]
  let baseStep = f.arguments[int(off+3)]
  let shiftStep = f.arguments[int(off+4)]
  let branch = f.arguments[int(off+5)]
  let base = store.slots.bIndex
  let shift = prefix.slots.bIndex
  let roles = [prefix.slots.aIndex, shift, prefix.slots.destinationIndex, base, branch.slots.bIndex]
  for i in 0..<5:
    # Data, shift, byte destination, address and bound must not overwrite another live role.
    for j in i+1..<5:
      # Aliases retain the original checked loop instead of assuming a stable word or branch bound.
      if roles[i] == roles[j]: return false
  uint32(branch.x shr 32) == off and store.slots.aIndex == prefix.slots.destinationIndex and
    baseStep.slots.aIndex == base and baseStep.slots.bIndex == base and baseStep.x == 1 and
    shiftStep.slots.aIndex == shift and shiftStep.slots.bIndex == shift and shiftStep.x == 8 and
    branch.slots.aIndex == base

proc flatChargedWordLoop(f: var FlatFrame, off: uint32): uint32 =
  ## Replace four fully affordable, valid byte iterations with their equivalent checked word store.
  while f.remaining >= 20:
    # Four complete original blocks need twenty attempts and at most four nonoverflowing prices.
    let header = f.arguments[int(off)]
    if header.x > high(uint64) div 4:
      # Unknown large price combinations keep the original per-block affordability checks.
      break
    let charged = header.x*(if f.info.blockCharged: 3'u64 else: 4'u64)
    if uint64(f.info.gas) < charged:
      # The scalar path may still complete fewer blocks before its exact out-of-gas boundary.
      break
    let prefix = f.arguments[int(off+1)]
    let store = f.arguments[int(off+2)]
    let branch = f.arguments[int(off+5)]
    let shift = uint64(f.info.registers[prefix.slots.bIndex])
    let base = uint64(f.info.registers[store.slots.bIndex])
    let bound = uint64(f.info.registers[branch.slots.bIndex])
    if (shift and 31) != 0 or base > high(uint64)-4 or base+4 > bound:
      # Shifts 0/8/16/24 extract one low word; base+1..3 cannot equal the opcode 171 bound.
      # Wrapped or other loop coordinates retain the original != predicate and bytewise order.
      break
    let address = (base+store.x) and 0xffffffff'u64
    if address < 65536 or address > uint64(high(uint32))-4:
      # Match the existing conservative four-byte fast-store extent; ambiguous/faulting spans stay scalar.
      break
    var valid = false
    if address >= f.stackBase:
      # The complete private stack extent has the same positive proof used by flatStore[4].
      valid = f.stack.len >= 4 and address-f.stackBase <= uint64(f.stack.len-4)
    elif address >= f.rwBase:
      # RO, fragmented and cross-permission layouts cannot qualify through this writable region.
      valid = f.rw.len >= 4 and address-f.rwBase <= uint64(f.rw.len-4)
    if not valid:
      # A bytewise prefix must remain observable before a later fault when the word extent is unavailable.
      break
    let word = uint64(f.info.registers[prefix.slots.aIndex]) and 0xffffffff'u64
    # No host/control exit or quota boundary can occur inside these four proven complete iterations.
    # The original checked store repeats the positive extent proof and owns dirty-page publication.
    let stored = flatStore[4](f, off+2, address, word)
    assert stored
    # Only a successful full extent permits the original twenty-attempt and four-block state projection.
    f.remaining-=20
    f.reservation = off or flatReservationHeaderFlag
    f.info.gas = MachineGas(uint64(f.info.gas)-charged)
    f.info.registers[prefix.slots.destinationIndex] = RegisterValue(word shr 24)
    f.info.registers[store.slots.bIndex] = RegisterValue(base+4)
    f.info.registers[prefix.slots.bIndex] = RegisterValue(shift+32)
    when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
      inc f.x86CheckedWordGroups
    var destination = flatStop
    flatBranchSelect(f, branch, 171, destination)
    if destination != off:
      # The fourth genuine branch may leave; its exact cached destination and paid reset still apply.
      return destination
  # Every declined batch starts the untouched original checked loop, including its partial/fault behavior.
  flatChargedStoreLoop(f, off)

proc flatChargedStoreCold(f: var FlatFrame, off: uint32): uint32 =
  ## Retain ordinary checked dispatch until the terminal branch has validated both genuine arms.
  flatReserve(f, off)
  let selected = f.handlers[int(off+1)]
  let outcome = selected(f, off+1)
  let cached: FlatHandler = flatBranch[171]
  if f.barrier == flatStop and f.handlers[int(off+5)] == cached:
    # Partial barriers and unresolved/invalid branches never authorize the complete-loop worker.
    let args = f.arguments[int(off+5)]
    let yes = uint32(args.x shr 32)
    let no = args.y
    if (yes == off and no != off) or (no == off and yes != off):
      # Cache only source coordinates; no register, memory, gas or invocation pointer survives here.
      if flatWordShape(f, off):
        # Only this additional sealed dataflow permits four-byte projection inside the resident loop.
        f.handlers[int(off)] = flatChargedWordLoop
      else:
        # Other genuine five-operation self-loops keep their established checked per-iteration worker.
        f.handlers[int(off)] = flatChargedStoreLoop
      when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
        inc f.x86CheckedStoreSelections
  outcome

when defined(pvmX86Jit) and defined(pvmX86CheckedStoreReceipt):
  func flatX86CheckedStoreStatistics*(f: FlatFrame): array[3, uint64] =
    ## Receipt-only counts prove checked-loop installation and completed byte and word work.
    [f.x86CheckedStoreSelections, f.x86CheckedByteBlocks, f.x86CheckedWordGroups]

proc flatBadControl[Code: static[int]](f: var FlatFrame, off: uint32): uint32 =
  ## Invalid destinations retain GP load mutations but never permit an unselected invalid conditional arm to escape validation.
  when Code == 80:
    let a = f.arguments[int(off)]
    f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  flatStopExit(f, off, oracle.StepExit.Panic)

proc flatDynamic[Code: static[int]; Single: static[bool]](f: var FlatFrame, off: uint32): uint32 =
  ## Full sentinel/alignment/table membership rules match our control worker, with predecoded dense target facts.
  let a = f.arguments[int(off)]
  let base = when Code == 50: uint64(f.info.registers[a.slots.aIndex]) else: uint64(
      f.info.registers[a.slots.bIndex])
  let delta = when Code == 50: a.x else: flatSext32(a.y)
  let address = (base+delta) and 0xffffffff'u64
  when Code == 180: f.info.registers[a.slots.aIndex] = RegisterValue(a.x)
  if address == 0xffff0000'u64: return flatStopExit(f, off, oracle.StepExit.Halt)
  if address == 0 or (address and 1) != 0: return flatStopExit(f, off, oracle.StepExit.Panic)
  let index = address div 2-1
  let slot = int(index and 255'u64)
  let known = f.dynamicOffsets[slot]
  if (known shr 32) == index+1:
    f.info.blockCharged = false
    return uint32(known and 0xffffffff'u64)-1
  var target = FlatTarget(pc: 0, valid: false)
  when Single:
    # A single instruction checks only its chosen original table ordinal; it never decodes the full table.
    let found = jumpTarget(f.plan.source, JumpIndex(index))
    if found.error != ProgramError.None: return flatStopExit(f, off, oracle.StepExit.Panic)
    let starts = basicBlockStart(f.plan.source, found.value)
    target = FlatTarget(pc: uint32(uint64(found.value) and 0xffffffff'u64),
      valid: starts.error == ProgramError.None and starts.value)
  else:
    # Ordinary prepared execution retains the qualified dense-table lookup without a runtime mode branch.
    if index >= uint64(f.plan.jumps.len): return flatStopExit(f, off, oracle.StepExit.Panic)
    target = f.plan.jumps[int(index)]
  if not target.valid: return flatStopExit(f, off, oracle.StepExit.Panic)
  let resolved = flatResolve(f, target.pc)
  if resolved == flatStop: return flatResolutionFailure(f, off)
  f.dynamicOffsets[slot] = ((index+1) shl 32) or uint64(resolved+1)
  f.info.blockCharged = false
  resolved

proc flatHost(f: var FlatFrame, off: uint32): uint32 =
  ## A genuine host exit is source-bound and preserves the sign-extended immediate in its complete register-width domain.
  f.hostCall = oracle.HostCallId(f.arguments[int(off)].x)
  flatStopExit(f, off, oracle.StepExit.Host)

proc flatTrap(f: var FlatFrame, off: uint32): uint32 =
  ## Recursive terminal normalization stays on the rare exit path.
  flatStopExit(f, off, oracle.StepExit.Panic)

proc flatNoop(f: var FlatFrame, off: uint32): uint32 =
  ## Available for isolated opcode witnesses; ordinary compilation folds unlikely while retaining source-budget facts.
  off+1

proc flatInvalid(f: var FlatFrame, off: uint32): uint32 =
  ## A missing successor for a nonterminator is a local invalid-machine refusal, not a fabricated guest trap.
  flatLocal(f, off, oracle.StepError.InvalidMachine)

func flatHandler(code: byte, valid, fallthrough: bool): nil FlatHandler {.inline.} =
  ## One canonical literal handler table is shared by ordinary preparation and specialized second-instruction selection.
  if not fallthrough and code notin {0'u8, 1'u8, 40'u8, 50'u8, 80'u8..90'u8, 170'u8..175'u8, 180'u8}:
    return flatInvalid
  case code
  of 0: flatTrap
  of 1: (if valid: flatJump[1] else: flatBadControl[1])
  of 2: flatNoop
  of 10: flatHost
  of 20: flatRegister[20]
  of 30: flatMemoryWorker[1, false, false, false, true, true, false]
  of 31: flatMemoryWorker[2, false, false, false, true, true, false]
  of 32: flatMemoryWorker[4, false, false, false, true, true, false]
  of 33: flatMemoryWorker[8, false, false, false, true, true, false]
  of 40: (if valid: flatJump[40] else: flatBadControl[40])
  of 50: flatDynamic[50, false]
  of 51: flatRegister[51]
  of 52: flatMemoryWorker[1, true, false, false, false, true, false]
  of 53: flatMemoryWorker[1, true, true, false, false, true, false]
  of 54: flatMemoryWorker[2, true, false, false, false, true, false]
  of 55: flatMemoryWorker[2, true, true, false, false, true, false]
  of 56: flatMemoryWorker[4, true, false, false, false, true, false]
  of 57: flatMemoryWorker[4, true, true, false, false, true, false]
  of 58: flatMemoryWorker[8, true, false, false, false, true, false]
  of 59: flatMemoryWorker[1, false, false, false, false, true, false]
  of 60: flatMemoryWorker[2, false, false, false, false, true, false]
  of 61: flatMemoryWorker[4, false, false, false, false, true, false]
  of 62: flatMemoryWorker[8, false, false, false, false, true, false]
  of 70: flatMemoryWorker[1, false, false, true, true, true, false]
  of 71: flatMemoryWorker[2, false, false, true, true, true, false]
  of 72: flatMemoryWorker[4, false, false, true, true, true, false]
  of 73: flatMemoryWorker[8, false, false, true, true, true, false]
  of 80: (if valid: flatJump[80] else: flatBadControl[80])
  of 81: (if valid and fallthrough: flatUnresolvedBranch[81] else: flatBadControl[81])
  of 82: (if valid and fallthrough: flatUnresolvedBranch[82] else: flatBadControl[82])
  of 83: (if valid and fallthrough: flatUnresolvedBranch[83] else: flatBadControl[83])
  of 84: (if valid and fallthrough: flatUnresolvedBranch[84] else: flatBadControl[84])
  of 85: (if valid and fallthrough: flatUnresolvedBranch[85] else: flatBadControl[85])
  of 86: (if valid and fallthrough: flatUnresolvedBranch[86] else: flatBadControl[86])
  of 87: (if valid and fallthrough: flatUnresolvedBranch[87] else: flatBadControl[87])
  of 88: (if valid and fallthrough: flatUnresolvedBranch[88] else: flatBadControl[88])
  of 89: (if valid and fallthrough: flatUnresolvedBranch[89] else: flatBadControl[89])
  of 90: (if valid and fallthrough: flatUnresolvedBranch[90] else: flatBadControl[90])
  of 100: flatRegister[100]
  of 101: flatRegister[101]
  of 102: flatRegister[102]
  of 103: flatRegister[103]
  of 104: flatRegister[104]
  of 105: flatRegister[105]
  of 106: flatRegister[106]
  of 107: flatRegister[107]
  of 108: flatRegister[108]
  of 109: flatRegister[109]
  of 110: flatRegister[110]
  of 120: flatMemoryWorker[1, false, false, true, false, true, false]
  of 121: flatMemoryWorker[2, false, false, true, false, true, false]
  of 122: flatMemoryWorker[4, false, false, true, false, true, false]
  of 123: flatMemoryWorker[8, false, false, true, false, true, false]
  of 124: flatMemoryWorker[1, true, false, true, false, true, false]
  of 125: flatMemoryWorker[1, true, true, true, false, true, false]
  of 126: flatMemoryWorker[2, true, false, true, false, true, false]
  of 127: flatMemoryWorker[2, true, true, true, false, true, false]
  of 128: flatMemoryWorker[4, true, false, true, false, true, false]
  of 129: flatMemoryWorker[4, true, true, true, false, true, false]
  of 130: flatMemoryWorker[8, true, false, true, false, true, false]
  of 131: flatRegister[131]
  of 132: flatRegister[132]
  of 133: flatRegister[133]
  of 134: flatRegister[134]
  of 135: flatRegister[135]
  of 136: flatRegister[136]
  of 137: flatRegister[137]
  of 138: flatRegister[138]
  of 139: flatRegister[139]
  of 140: flatRegister[140]
  of 141: flatRegister[141]
  of 142: flatRegister[142]
  of 143: flatRegister[143]
  of 144: flatRegister[144]
  of 145: flatRegister[145]
  of 146: flatRegister[146]
  of 147: flatRegister[147]
  of 148: flatRegister[148]
  of 149: flatRegister[149]
  of 150: flatRegister[150]
  of 151: flatRegister[151]
  of 152: flatRegister[152]
  of 153: flatRegister[153]
  of 154: flatRegister[154]
  of 155: flatRegister[155]
  of 156: flatRegister[156]
  of 157: flatRegister[157]
  of 158: flatRegister[158]
  of 159: flatRegister[159]
  of 160: flatRegister[160]
  of 161: flatRegister[161]
  of 170: (if valid and fallthrough: flatUnresolvedBranch[170] else: flatBadControl[170])
  of 171: (if valid and fallthrough: flatUnresolvedBranch[171] else: flatBadControl[171])
  of 172: (if valid and fallthrough: flatUnresolvedBranch[172] else: flatBadControl[172])
  of 173: (if valid and fallthrough: flatUnresolvedBranch[173] else: flatBadControl[173])
  of 174: (if valid and fallthrough: flatUnresolvedBranch[174] else: flatBadControl[174])
  of 175: (if valid and fallthrough: flatUnresolvedBranch[175] else: flatBadControl[175])
  of 180: flatDynamic[180, false]
  of 190: flatRegister[190]
  of 191: flatRegister[191]
  of 192: flatRegister[192]
  of 193: flatRegister[193]
  of 194: flatRegister[194]
  of 195: flatRegister[195]
  of 196: flatRegister[196]
  of 197: flatRegister[197]
  of 198: flatRegister[198]
  of 199: flatRegister[199]
  of 200: flatRegister[200]
  of 201: flatRegister[201]
  of 202: flatRegister[202]
  of 203: flatRegister[203]
  of 204: flatRegister[204]
  of 205: flatRegister[205]
  of 206: flatRegister[206]
  of 207: flatRegister[207]
  of 208: flatRegister[208]
  of 209: flatRegister[209]
  of 210: flatRegister[210]
  of 211: flatRegister[211]
  of 212: flatRegister[212]
  of 213: flatRegister[213]
  of 214: flatRegister[214]
  of 215: flatRegister[215]
  of 216: flatRegister[216]
  of 217: flatRegister[217]
  of 218: flatRegister[218]
  of 219: flatRegister[219]
  of 220: flatRegister[220]
  of 221: flatRegister[221]
  of 222: flatRegister[222]
  of 223: flatRegister[223]
  of 224: flatRegister[224]
  of 225: flatRegister[225]
  of 226: flatRegister[226]
  of 227: flatRegister[227]
  of 228: flatRegister[228]
  of 229: flatRegister[229]
  of 230: flatRegister[230]
  else: nil # Unsupported future opcodes never become guest traps or fabricated handlers.

func flatRegisterPairHandler(code: byte): nil FlatHandler =
  ## Only the complete existing register opcode set can provide a first-instruction prefix.
  case code
  of 20: flatRegisterPair[20]
  of 51: flatRegisterPair[51]
  of 100: flatRegisterPair[100]
  of 101: flatRegisterPair[101]
  of 102: flatRegisterPair[102]
  of 103: flatRegisterPair[103]
  of 104: flatRegisterPair[104]
  of 105: flatRegisterPair[105]
  of 106: flatRegisterPair[106]
  of 107: flatRegisterPair[107]
  of 108: flatRegisterPair[108]
  of 109: flatRegisterPair[109]
  of 110: flatRegisterPair[110]
  of 131: flatRegisterPair[131]
  of 132: flatRegisterPair[132]
  of 133: flatRegisterPair[133]
  of 134: flatRegisterPair[134]
  of 135: flatRegisterPair[135]
  of 136: flatRegisterPair[136]
  of 137: flatRegisterPair[137]
  of 138: flatRegisterPair[138]
  of 139: flatRegisterPair[139]
  of 140: flatRegisterPair[140]
  of 141: flatRegisterPair[141]
  of 142: flatRegisterPair[142]
  of 143: flatRegisterPair[143]
  of 144: flatRegisterPair[144]
  of 145: flatRegisterPair[145]
  of 146: flatRegisterPair[146]
  of 147: flatRegisterPair[147]
  of 148: flatRegisterPair[148]
  of 149: flatRegisterPair[149]
  of 150: flatRegisterPair[150]
  of 151: flatRegisterPair[151]
  of 152: flatRegisterPair[152]
  of 153: flatRegisterPair[153]
  of 154: flatRegisterPair[154]
  of 155: flatRegisterPair[155]
  of 156: flatRegisterPair[156]
  of 157: flatRegisterPair[157]
  of 158: flatRegisterPair[158]
  of 159: flatRegisterPair[159]
  of 160: flatRegisterPair[160]
  of 161: flatRegisterPair[161]
  of 190: flatRegisterPair[190]
  of 191: flatRegisterPair[191]
  of 192: flatRegisterPair[192]
  of 193: flatRegisterPair[193]
  of 194: flatRegisterPair[194]
  of 195: flatRegisterPair[195]
  of 196: flatRegisterPair[196]
  of 197: flatRegisterPair[197]
  of 198: flatRegisterPair[198]
  of 199: flatRegisterPair[199]
  of 200: flatRegisterPair[200]
  of 201: flatRegisterPair[201]
  of 202: flatRegisterPair[202]
  of 203: flatRegisterPair[203]
  of 204: flatRegisterPair[204]
  of 205: flatRegisterPair[205]
  of 206: flatRegisterPair[206]
  of 207: flatRegisterPair[207]
  of 208: flatRegisterPair[208]
  of 209: flatRegisterPair[209]
  of 210: flatRegisterPair[210]
  of 211: flatRegisterPair[211]
  of 212: flatRegisterPair[212]
  of 213: flatRegisterPair[213]
  of 214: flatRegisterPair[214]
  of 215: flatRegisterPair[215]
  of 216: flatRegisterPair[216]
  of 217: flatRegisterPair[217]
  of 218: flatRegisterPair[218]
  of 219: flatRegisterPair[219]
  of 220: flatRegisterPair[220]
  of 221: flatRegisterPair[221]
  of 222: flatRegisterPair[222]
  of 223: flatRegisterPair[223]
  of 224: flatRegisterPair[224]
  of 225: flatRegisterPair[225]
  of 226: flatRegisterPair[226]
  of 227: flatRegisterPair[227]
  of 228: flatRegisterPair[228]
  of 229: flatRegisterPair[229]
  of 230: flatRegisterPair[230]
  else: nil

func flatMemoryPairHandler(code: byte): nil FlatHandler =
  ## Only a successful first checked memory operation invokes the original second handler.
  case code
  of 30: flatMemoryWorker[1, false, false, false, true, true, true]
  of 31: flatMemoryWorker[2, false, false, false, true, true, true]
  of 32: flatMemoryWorker[4, false, false, false, true, true, true]
  of 33: flatMemoryWorker[8, false, false, false, true, true, true]
  of 52: flatMemoryWorker[1, true, false, false, false, true, true]
  of 53: flatMemoryWorker[1, true, true, false, false, true, true]
  of 54: flatMemoryWorker[2, true, false, false, false, true, true]
  of 55: flatMemoryWorker[2, true, true, false, false, true, true]
  of 56: flatMemoryWorker[4, true, false, false, false, true, true]
  of 57: flatMemoryWorker[4, true, true, false, false, true, true]
  of 58: flatMemoryWorker[8, true, false, false, false, true, true]
  of 59: flatMemoryWorker[1, false, false, false, false, true, true]
  of 60: flatMemoryWorker[2, false, false, false, false, true, true]
  of 61: flatMemoryWorker[4, false, false, false, false, true, true]
  of 62: flatMemoryWorker[8, false, false, false, false, true, true]
  of 70: flatMemoryWorker[1, false, false, true, true, true, true]
  of 71: flatMemoryWorker[2, false, false, true, true, true, true]
  of 72: flatMemoryWorker[4, false, false, true, true, true, true]
  of 73: flatMemoryWorker[8, false, false, true, true, true, true]
  of 120: flatMemoryWorker[1, false, false, true, false, true, true]
  of 121: flatMemoryWorker[2, false, false, true, false, true, true]
  of 122: flatMemoryWorker[4, false, false, true, false, true, true]
  of 123: flatMemoryWorker[8, false, false, true, false, true, true]
  of 124: flatMemoryWorker[1, true, false, true, false, true, true]
  of 125: flatMemoryWorker[1, true, true, true, false, true, true]
  of 126: flatMemoryWorker[2, true, false, true, false, true, true]
  of 127: flatMemoryWorker[2, true, true, true, false, true, true]
  of 128: flatMemoryWorker[4, true, false, true, false, true, true]
  of 129: flatMemoryWorker[4, true, true, true, false, true, true]
  of 130: flatMemoryWorker[8, true, false, true, false, true, true]
  else: nil

proc flatFact(decoded: ProgramResult[Instruction], priceIndex: uint32): FlatFact =
  ## Seal genuine operands once for either admission path; extracted mutable instructions cannot grant target facts.
  assert decoded.error == ProgramError.None
  let item = decoded.value
  let pc = uint64(item.address)
  assert pc <= uint64(high(uint32))-25
  let next = pc+1+uint64(item.skip)
  var target = 0'u64
  if item.opcode == 1: target = next
  elif item.displacement < 0:
    if uint64(-item.displacement) <= pc: target = pc-uint64(-item.displacement)
  else: target = pc+uint64(item.displacement)
  let valid = instructionTargetStartsBlock(decoded)
  let fallthrough = instructionHasFallthrough(decoded)
  var args = FlatArgs(x: uint64(item.x), y: uint32(uint64(item.y) and 0xffffffff'u64),
      slots: instructionRegisters(decoded))
  if item.opcode in {1'u8, 40'u8, 80'u8}: args.y = uint32(target and 0xffffffff'u64)
  elif item.opcode in {81'u8..90'u8, 170'u8..175'u8}:
    args.x = (args.x and 0xffffffff'u64) or ((target and 0xffffffff'u64) shl 32)
    args.y = uint32(next)
  FlatFact(args: args, handler: flatHandler(item.opcode, valid, fallthrough),
    pc: uint32(pc), next: uint32(next), sourceCount: 0, priceIndex: priceIndex,
    opcode: item.opcode, ending: terminatesBlock(item.opcode), fallthrough: fallthrough)

proc prepareFlatPlan*(source: Program, cycles: GasCycleLimit, limits: FlatLimits,
    allowNative: bool = true): FlatResult[FlatPlan] =
  ## Capture genuine complete instruction facts and containing-block pricing inputs before execution, preserving the explicit preparation boundary.
  if not validFlatLimits(limits): return FlatResult[FlatPlan](status: FlatError.InvalidPolicy)
  let extent = codeLength(source)
  if extent.error != ProgramError.None or extent.value == 0:
    return FlatResult[FlatPlan](status: FlatError.InvalidProgram)
  if extent.value > uint64(limits.codeBytes): return FlatResult[FlatPlan](
      status: FlatError.CodeLimitExceeded)
  assert sizeof(FlatArgs) == 16
  # The admission count occupies existing alignment padding on the supported 64-bit targets.
  when sizeof(pointer) == 8: assert sizeof(FlatFact) == 48
  var owner = FlatPlan(source: source, limits: limits, facts: @[], factAt: newSeq[int](int(
      extent.value)), pricePcs: @[
    ], cycles: cycles, jumps: @[], allowNative: allowNative, singleStep: false)
  for i in 0..<owner.factAt.len: owner.factAt[i] = -1
  var pc = 0'u64
  var priceIndex = 0'u32
  var begins = true
  while pc < extent.value:
    if uint64(owner.facts.len) >= uint64(limits.facts):
      return FlatResult[FlatPlan](status: FlatError.FactLimitExceeded)
    let decoded = instruction(source, CodeAddress(pc))
    if decoded.error != ProgramError.None: return FlatResult[FlatPlan](
        status: FlatError.InvalidProgram)
    let item = decoded.value
    # This sequential walk already knows whether the preceding instruction ended a block.
    if begins:
      priceIndex = uint32(owner.pricePcs.len)
      owner.pricePcs.add(item.address)
    let fact = flatFact(decoded, priceIndex)
    owner.factAt[int(pc)] = owner.facts.len
    owner.facts.add(fact)
    begins = fact.ending
    pc = uint64(fact.next)
  var count = 0'u32
  var nodes = 0'u32
  var at = owner.facts.len
  while at > 0:
    dec at
    if owner.facts[at].ending:
      # A genuine terminator begins the next reverse suffix; folded noops occupy no executable node.
      count = 1
      nodes = 0
    else: inc count
    if owner.facts[at].opcode != 2: inc nodes
    owner.facts[at].sourceCount = count
    owner.facts[at].nodeCount = nodes
  var ordinal = 0'u64
  while true:
    let resolved = jumpTarget(source, JumpIndex(ordinal))
    if resolved.error != ProgramError.None: break
    if ordinal >= uint64(limits.jumps): return FlatResult[FlatPlan](
        status: FlatError.JumpLimitExceeded)
    let target = resolved.value
    let valid = basicBlockStart(source, target)
    owner.jumps.add(FlatTarget(pc: uint32(uint64(target) and 0xffffffff'u64),
      valid: valid.error == ProgramError.None and valid.value))
    inc ordinal

  FlatResult[FlatPlan](status: FlatError.None, completed: move(owner))

proc prepareSingleFlatPlan*(source: Program, pc: CodeAddress,
    cycles: GasCycleLimit): FlatResult[FlatPlan] =
  ## Admit exactly one genuine instruction; ordinary source/profile checks precede any mutable frame allocation.
  let limits = defaultFlatLimits()
  let extent = codeLength(source)
  if extent.error != ProgramError.None: return FlatResult[FlatPlan](
      status: FlatError.InvalidProgram)
  if extent.value > uint64(limits.codeBytes): return FlatResult[FlatPlan](
      status: FlatError.CodeLimitExceeded)
  let decoded = instruction(source, pc)
  if decoded.error != ProgramError.None: return FlatResult[FlatPlan](
      status: FlatError.InvalidProgram)
  var fact = flatFact(decoded, 0)
  fact.sourceCount = 1
  fact.nodeCount = 1
  if fact.opcode == 50: fact.handler = flatDynamic[50, true]
  elif fact.opcode == 180: fact.handler = flatDynamic[180, true]
  FlatResult[FlatPlan](status: FlatError.None, completed: FlatPlan(source: source,
    facts: @[fact], factAt: @[], pricePcs: @[], cycles: cycles, jumps: @[], limits: limits,
    allowNative: false, singleStep: true))

proc newFlatPlan*(source: Program, cycles: GasCycleLimit): FlatPlan =
  ## Local witness convenience only; application admission uses prepareFlatPlan and checks its typed result.
  var prepared = prepareFlatPlan(source, cycles, defaultFlatLimits())
  assert prepared.error == FlatError.None
  takeValue(prepared)

proc flatEmit(f: var FlatFrame, handler: FlatHandler, args: FlatArgs, site: uint32) =
  ## Parallel contiguous arrays preserve a 24-byte handler/argument payload plus a source index for rare exits.
  assert f.handlers.len < 2147483646
  f.handlers.add(handler)
  f.arguments.add(args)
  f.sites.add(site)

proc flatPrice(f: var FlatFrame, start: CodeAddress, cost: var uint64): oracle.StepError =
  ## Query the selected exact-owner pricing policy only when preparing a previously unseen suffix.
  if f.pricingKind == 1:
    let price = blockGas(f.pricingPlan, start)
    if price.error != GasPlanError.None: return oracle.StepError.InvalidGasPlan
    cost = uint64(price.value)
    return oracle.StepError.None
  if f.pricingKind == 2:
    let price = blockGas(f.pricingMemo, start)
    case price.error
    of GasMemoError.None:
      cost = uint64(price.value)
      return oracle.StepError.None
    of GasMemoError.CycleLimitExceeded: return oracle.StepError.GasCycleLimitExceeded
    of GasMemoError.NegativeBranchTarget: return oracle.StepError.NegativeBranchTarget
    else: return oracle.StepError.InvalidGasMemo
  let price = blockGas(f.plan.source, start, f.plan.cycles)
  case price.error
  of GasError.None:
    cost = uint64(price.value)
    oracle.StepError.None
  of GasError.CycleLimitExceeded: oracle.StepError.GasCycleLimitExceeded
  of GasError.NegativeBranchTarget: oracle.StepError.NegativeBranchTarget
  else: oracle.StepError.InvalidMachine

proc flatMemoCharge(f: var FlatFrame, off: uint32): uint32 =
  ## Preparation alone must not populate a caller's lazy memo; only an attempted unpaid entry queries it.
  if f.remaining > 0 and not f.info.blockCharged:
    let fact = f.plan.facts[int(f.sites[int(off)])]
    var cost = 0'u64
    let priced = flatPrice(f, f.plan.pricePcs[int(fact.priceIndex)], cost)
    if priced != oracle.StepError.None: return flatLocal(f, off, priced)
    f.arguments[int(off)].x = cost
    f.handlers[int(off)] = flatCharge
  flatCharge(f, off)

proc flatSingleEnd(f: var FlatFrame, off: uint32): uint32 =
  ## A scalar successor publishes one completed source attempt without preparing its destination block.
  f.info.pc = CodeAddress(f.arguments[int(off)].x)
  f.reason = oracle.StepError.StepLimitExceeded
  f.stoppedAt = off
  f.attemptedExit = false
  flatStop

proc flatSingleResolve(f: var FlatFrame, pc: uint32): uint32 =
  ## At most two conditional arms add endpoint nodes; the same genuine target checks precede transfer.
  let decoded = instruction(f.plan.source, CodeAddress(uint64(pc)))
  if decoded.error != ProgramError.None: return flatStop
  assert f.handlers.len < 5
  let offset = uint32(f.handlers.len)
  flatEmit(f, flatSingleEnd, FlatArgs(x: uint64(pc), y: 0, slots: default(RegisterSlots)), 0)
  offset

proc flatResolve(f: var FlatFrame, pc: uint32): uint32 =
  ## A dense positive map and monotone stream preserve stable offset links; interior resume creates a prepaid suffix header once.
  if f.preparationFailure != FlatError.None: return flatStop
  if f.plan.singleStep: return flatSingleResolve(f, pc)
  if uint64(pc) >= uint64(f.plan.factAt.len): return flatStop
  if f.compiledForPc.len > 0:
    let packed = f.compiledForPc[int(pc)]
    if packed != 0:
      let value = packed-1
      if (value and 0x80000000'u32) != 0: return value and 0x7fffffff'u32
  let start = f.plan.factAt[int(pc)]
  if start < 0: return flatStop
  # Stable offset links forbid eviction inside execution. Refuse a whole suffix before its first allocation/map write.
  let ceiling = uint64(f.plan.limits.nodes)
  let occupied = uint64(f.handlers.len)
  assert occupied <= ceiling
  let available = ceiling-occupied
  # Sealed non-noop suffix counts make admission constant-time, independently of guest source quotas.
  let required = 1'u64+uint64(f.plan.facts[start].nodeCount)
  if required > available:
    f.preparationFailure = FlatError.StreamLimitExceeded
    return flatStop
  # Node folding does not erase preparation cost: reserve both the emitted suffix span and its whole containing price span.
  let pricePc = f.plan.pricePcs[int(f.plan.facts[start].priceIndex)]
  let priceFact = f.plan.factAt[int(uint64(pricePc))]
  assert priceFact >= 0
  let neededWork = uint64(f.plan.facts[start].sourceCount)+uint64(f.plan.facts[
      priceFact].sourceCount)
  let workLimit = uint64(f.plan.limits.preparation)
  assert f.preparationUsed <= workLimit
  if neededWork > workLimit-f.preparationUsed:
    f.preparationFailure = FlatError.PreparationLimitExceeded
    return flatStop
  f.preparationUsed+=neededWork
  if f.compiledForPc.len == 0: f.compiledForPc = newSeq[uint32](f.plan.factAt.len)
  let origin = uint32(f.handlers.len)
  var index = start
  var first = true
  # A fixed original node ends every short continuation chain, including unoptimized builds.
  var chainLimit = 4
  when defined(pvmX86Jit):
    if f.plan.allowNative: chainLimit = 2 # Keep the unmeasured x86 native fallback layout.
  var continuations = 0
  while index < f.plan.facts.len:
    let fact = f.plan.facts[index]
    let coordinate = uint32(f.handlers.len)
    let packed = f.compiledForPc[int(fact.pc)]
    if packed == 0 or ((packed-1) and 0x80000000'u32) == 0:
      # An overlapping suffix may replace an interior coordinate, never an already published complete entry header.
      f.compiledForPc[int(fact.pc)] = (coordinate or (if first: 0x80000000'u32 else: 0'u32))+1
    if first:
      # Only a newly emitted header prices its genuine containing block. Its existing sealed charge/error node is the memo; interior suffixes may price once each.
      var charge: FlatHandler = flatCharge
      var needed = 0'u64
      if f.pricingKind == 2:
        # Even eagerly linked untaken branches must not create observable memo entries.
        charge = flatMemoCharge
      else:
        let priced = flatPrice(f, f.plan.pricePcs[int(fact.priceIndex)], needed)
        case priced
        of oracle.StepError.None:
          # Only these measured complete shapes specialize normal headers; folded prefixes and failed prices stay ordinary.
          if fact.sourceCount == 2 and index+1 < f.plan.facts.len and fact.opcode == 131 and
              f.plan.facts[index+1].opcode == 88:
            charge = flatChargedShapeCold[131, -1, 88]
          elif fact.sourceCount == 3 and index+2 < f.plan.facts.len:
            let second = f.plan.facts[index+1].opcode
            let last = f.plan.facts[index+2].opcode
            if fact.opcode == 200 and second == 139 and last == 82:
              charge = flatChargedShapeCold[200, 139, 82]
            elif fact.opcode == 151 and second == 152 and last == 173:
              charge = flatChargedShapeCold[151, 152, 173]
          elif fact.sourceCount == 5 and index+4 < f.plan.facts.len and f.pricingKind == 0:
            # Only this sealed adjacent shape is selected; native x86 has no store publisher for it.
            if fact.opcode == 198 and f.plan.facts[index+1].opcode == 120 and
                f.plan.facts[index+2].opcode == 149 and f.plan.facts[index+3].opcode == 149 and
                f.plan.facts[index+4].opcode == 171:
              when defined(pvmArm64Jit) and not defined(pvmX86Jit):
                # ARM native publication owns this store-loop entry; explicit interpretation keeps the checked worker.
                if not f.plan.allowNative:
                  charge = flatChargedStoreCold
              else:
                # X86 native and interpreted plans use the same source-proven checked word/store loop.
                charge = flatChargedStoreCold
        of oracle.StepError.GasCycleLimitExceeded: charge = flatChargeFailure[
            oracle.StepError.GasCycleLimitExceeded]
        of oracle.StepError.NegativeBranchTarget: charge = flatChargeFailure[
            oracle.StepError.NegativeBranchTarget]
        else: charge = flatChargeFailure[oracle.StepError.InvalidMachine]
      flatEmit(f, charge, FlatArgs(x: needed, y: fact.sourceCount, slots: default(RegisterSlots)),
          uint32(index))
      first = false
    var selected = fact.handler
    assert selected != nil
    if fact.opcode != 2:
      # Bounded continuation prefixes stop at an original worker before the next chain begins.
      if continuations < chainLimit-1 and fact.fallthrough:
        let first = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(
            fact.opcode) else: flatMemoryPairHandler(fact.opcode)
        if first != nil:
          selected = first
          # Only these trace-selected adjacent genuine register opcodes fuse; folded noops and other families retain existing dispatch.
          if index+1 < f.plan.facts.len:
            let second = f.plan.facts[index+1].opcode
            if fact.opcode == 151 and second == 152: selected = flatFusedRegisters[151, 152]
            elif fact.opcode == 200 and second == 139: selected = flatFusedRegisters[200, 139]
            elif fact.opcode == 149 and second == 149: selected = flatFusedRegisters[149, 149]
            elif fact.opcode == 131 and second == 88: selected = flatRegisterBranchCold[131, 88]
          inc continuations
        else: continuations = 0
      else: continuations = 0
      if selected != nil: flatEmit(f, selected, fact.args, uint32(index))
    if fact.ending: break
    inc index
  flatConsiderNative(f, origin)
  when NativeCheckedReadEnabled:
    # Only a newly emitted canonical-looking noop block can reach bounded discovery.
    if f.readProbe.observing and f.plan.facts[start].opcode == 2 and
        f.plan.facts[start].sourceCount in 4'u32..NativeReadFactLimit and
        f.plan.facts[index].opcode == 1:
      discoverReadProbe(f, origin, pc)
  origin

proc flatNativePure(f: var FlatFrame, off: uint32): uint32 =
  ## One shared control bridge: full paid original prefix first, fresh registers only, no native replay.
  let original = f.nativeOriginal
  assert original != nil and off == f.nativeEntry
  let span = nativeSpanInfo(f.nativeSession)
  if not nativeSpanReady(f.nativeSession) or f.pricingKind != 0 or
      f.barrier != flatStop or not f.info.blockCharged or
      span.epoch != f.nativeInstalledEpoch:
    return original(f, off)
  var reservedEnd = f.reservation
  if (reservedEnd and flatReservationHeaderFlag) != 0:
    let header = reservedEnd and not flatReservationHeaderFlag
    reservedEnd = f.sites[int(header)]+f.arguments[int(header)].y
  if reservedEnd <= span.last: return original(f, off)
  runNativeSpan(f.nativeSession, f.info.registers)
  span.past

func flatNativeHeader(f: FlatFrame, header, pc: uint32): bool =
  ## Accept only a materialized, ordinary, original block header at this exact source PC.
  if header >= NativeEntryLimit or uint64(header) >= uint64(f.handlers.len) or
      uint64(header) >= uint64(f.sites.len) or uint64(pc) >= uint64(f.compiledForPc.len):
    return false
  if f.handlers[int(header)] != flatCharge or
      f.compiledForPc[int(pc)] != (header or flatReservationHeaderFlag)+1: return false
  let ordinal = f.sites[int(header)]
  if uint64(ordinal) >= uint64(f.plan.facts.len): return false
  let fact = f.plan.facts[int(ordinal)]
  fact.pc == pc and uint64(fact.priceIndex) < uint64(f.plan.pricePcs.len) and
    uint64(f.plan.pricePcs[int(fact.priceIndex)]) == uint64(pc)

proc flatLoopCertificate(f: FlatFrame, span: NativeSpanInfo): NativeLoopInfo =
  ## Check the one selected prefix against resolved source, without admitting or pricing another node.
  result = default(NativeLoopInfo)
  if f.plan == nil or f.plan.singleStep or f.pricingKind != 0 or
      f.preparationFailure != FlatError.None or span.epoch != nativeEpoch(f.nativeSession):
    return
  if span.len < NativeMinimumOperations or span.len >= NativeSpanOperations or span.entry == 0 or
      span.past >= NativeEntryLimit or span.past <= span.entry or
      span.past-span.entry != uint32(span.len) or span.last < span.first or
      span.last-span.first != uint32(span.len-1) or
      uint64(span.last)+1 >= uint64(f.plan.facts.len) or int(span.past) >= f.handlers.len or
      int(span.past) >= f.arguments.len or int(span.past) >= f.sites.len: return
  let header = span.entry-1
  let first = f.plan.facts[int(span.first)]
  let terminal = f.plan.facts[int(span.last)+1]
  let rightKind = case terminal.opcode
    of 83: NativeLoopRightKind.Immediate
    of 172: NativeLoopRightKind.Register
    else: return
  let branchHandler: FlatHandler = if rightKind == NativeLoopRightKind.Immediate:
    flatBranch[83]
  else:
    flatBranch[172]
  let sourceSpan = uint32(span.len)+1
  if not flatNativeHeader(f, header, first.pc) or f.sites[int(header)] != span.first or
      f.arguments[int(header)].y != sourceSpan or first.sourceCount != sourceSpan or
      f.sites[int(span.past)] != span.last+1 or not terminal.ending or
      terminal.priceIndex != first.priceIndex or f.handlers[int(span.past)] != branchHandler:
    return
  let branch = f.arguments[int(span.past)]
  let exitHeader = branch.y
  if uint32(branch.x shr 32) != header or uint32(terminal.args.x shr 32) != first.pc or
      branch.slots != terminal.args.slots or (branch.x and 0xffffffff'u64) !=
        (terminal.args.x and 0xffffffff'u64) or
      (exitHeader >= header and exitHeader <= span.past) or
      not flatNativeHeader(f, exitHeader, terminal.args.y): return
  for index in 0..<span.len:
    # Each original scalar fact has exactly one body node, with no folded or crossing instruction.
    let ordinal = span.first+uint32(index)
    let node = int(span.entry)+index
    let fact = f.plan.facts[int(ordinal)]
    let args = f.arguments[node]
    if f.sites[node] != ordinal or fact.ending or not fact.fallthrough or
        fact.priceIndex != first.priceIndex or fact.next != f.plan.facts[int(ordinal)+1].pc or
        args.x != fact.args.x or args.slots != fact.args.slots or
        not matchesNativeOperation(f.nativeSession, index, fact.opcode, fact.args.slots,
          fact.args.x): return
  # The cached low word has been checked against the original branch fact.
  let immediate = if rightKind == NativeLoopRightKind.Immediate:
    flatSext32(uint32(branch.x and 0xffffffff'u64))
  else:
    0'u64
  result = NativeLoopInfo(header: header, exitHeader: exitHeader, sourceSpan: sourceSpan,
    price: f.arguments[int(header)].x, slots: branch.slots, rightKind: rightKind,
    rightImmediate: immediate)

proc flatPromoteNativeLoop(f: var FlatFrame) =
  ## Reconsider the same deferred prefix only after the checked segment has resolved its branch.
  if not nativePromotionOpen(f.nativeSession): return
  let loop = flatLoopCertificate(f, nativeSpanInfo(f.nativeSession))
  if loop.kind == NativeKind.ClosedRegisterLoop: promoteNativeLoop(f.nativeSession, loop)

proc flatNativeLoop(f: var FlatFrame, off: uint32): uint32 =
  ## The installed certificate is stable. Only an exact complete reservation authorizes first entry.
  let original = f.nativeOriginal
  assert original != nil
  let loop = nativeLoopInfo(f.nativeSession)
  if not nativeSpanReady(f.nativeSession) or loop.kind != NativeKind.ClosedRegisterLoop or
      nativeEpoch(f.nativeSession) != f.nativeInstalledEpoch or f.pricingKind != 0 or
      f.barrier != flatStop or
      not f.info.blockCharged or off != f.nativeEntry or off != loop.header+1 or
      f.reservation != (loop.header or flatReservationHeaderFlag) or
      f.handlers[int(loop.header)] != flatCharge or f.arguments[int(loop.header)].x != loop.price or
      f.arguments[int(loop.header)].y != loop.sourceSpan: return original(f, off)
  var context = NativeLoopContext(gas: uint64(f.info.gas), remaining: f.remaining, visits: 0)
  result = runNativeLoop(f.nativeSession, f.info.registers, context)
  # The checked successor sees an unstarted block, including on a failed native next-visit guard.
  f.info.gas = MachineGas(context.gas)
  f.remaining = context.remaining
  f.info.blockCharged = false
  f.reservation = loop.header or flatReservationHeaderFlag

when NativeCheckedReadEnabled:
  proc installFlatReadBody(f: var FlatFrame, info: NativeReadBodyInfo)

proc installNative(f: var FlatFrame) =
  ## Only the caller mutates its exclusively held stream; each image uses its own certificate.
  if f.pricingKind != 0 or f.nativeOriginal != nil: return
  when NativeCheckedReadEnabled:
    let read = nativeReadInfo(f.nativeSession)
    if read.epoch != 0:
      installFlatReadBody(f, read)
      return
  if not nativeSpanReady(f.nativeSession): return
  let span = nativeSpanInfo(f.nativeSession)
  let candidate = nativeLoopInfo(f.nativeSession)
  if candidate.kind == NativeKind.ClosedRegisterLoop:
    let loop = flatLoopCertificate(f, span)
    if loop.sourceSpan != candidate.sourceSpan or loop.header != candidate.header or
        loop.exitHeader != candidate.exitHeader or loop.price != candidate.price or
        loop.slots != candidate.slots or loop.rightKind != candidate.rightKind or
        loop.rightImmediate != candidate.rightImmediate:
      invalidateNativeStream(f.nativeSession)
      return
    f.nativeOriginal = f.handlers[int(span.entry)]
    f.nativeEntry = span.entry
    f.nativeInstalledEpoch = span.epoch
    f.handlers[int(span.entry)] = flatNativeLoop
    return
  if span.epoch != nativeEpoch(f.nativeSession) or int(span.entry) >= f.handlers.len or
      int(span.past) >= f.handlers.len or span.past <= span.entry: return
  if f.sites[int(span.entry)] != span.first or f.sites[int(span.past)-1] != span.last: return
  if f.nativeOriginal == nil:
    if int(span.last) >= f.plan.facts.len: return
    var operation = 0
    for ordinal in span.first..span.last:
      let fact = f.plan.facts[int(ordinal)]
      # Folded noops remain original attempts but emit no register operation.
      if fact.opcode == 2: continue
      if fact.ending or not fact.fallthrough or not matchesNativeOperation(f.nativeSession,
          operation, fact.opcode, fact.args.slots, fact.args.x):
        invalidateNativeStream(f.nativeSession)
        return
      inc operation
    if operation != span.len:
      invalidateNativeStream(f.nativeSession)
      return
    f.nativeOriginal = f.handlers[int(span.entry)]
    f.nativeEntry = span.entry
    f.nativeInstalledEpoch = span.epoch
    f.handlers[int(span.entry)] = flatNativePure

proc flatConsiderNative(f: var FlatFrame, origin: uint32) =
  ## Shared structural classification precedes any native cache/byte allocation and all ISA decisions.
  let epoch = nativeEpoch(f.nativeSession)
  if epoch == 0 or f.pricingKind != 0 or nativeSpanInfo(f.nativeSession).len != 0: return
  var index = max(origin, nativeScanStart(f.nativeSession))
  while int(index) < f.handlers.len and index < NativeEntryLimit:
    # Synthetic charge headers duplicate the next source site and never belong to a pure body.
    if int(index)+1 < f.sites.len and f.sites[int(index)] == f.sites[int(index)+1]:
      inc index
      continue
    var span = initNativeSpan(index, f.sites[int(index)], epoch)
    var at = index
    while int(at) < f.handlers.len and span.len < NativeSpanOperations:
      if int(at)+1 < f.sites.len and f.sites[int(at)] == f.sites[int(at)+1]: break
      let fact = f.plan.facts[int(f.sites[int(at)])]
      if fact.ending or not fact.fallthrough or
          not span.add(fact.opcode, fact.args.slots, fact.args.x, f.sites[int(at)], at+1): break
      inc at
    if span.len >= NativeMinimumOperations and int(span.past) < f.handlers.len:
      considerNativeSpan(f.nativeSession, span)
      return
    index = if at > index: at else: index+1
  completeNativeScan(f.nativeSession, index)

proc settledNativeWork*(f: FlatFrame, supplied: uint64): uint64 =
  ## Initial conservative allowlist: normal checked halt/host excludes its attempted terminal instruction.
  ## Local errors, faults/panics/OOG and mixed native receipts contribute no speculative completion credit.
  if f.reason != oracle.StepError.None or f.exit notin {oracle.StepExit.Halt,
      oracle.StepExit.Host} or (not f.attemptedExit) or f.remaining > supplied: return 0
  let attempted = supplied-f.remaining
  if attempted == 0: return 0
  attempted-1

proc flatCopySourcePage(memory: Memory, slot: int, expected: PageDescription,
    output: var openArray[byte]) =
  ## The retained mapping bounds this positional copy; matching metadata binds it to the same immutable owner.
  let copied = copyMemoryPage(memory, MemoryPageSlot(uint32(slot)), output)
  assert copied.error == MachineError.None
  assert copied.value.index == expected.index and copied.value.access == expected.access

proc resetFlatFrame*(f: var FlatFrame, info: MachineInfo) =
  ## Restore input outside the execution clock, preserving the explicit reset boundary; cached code/links alone persist.
  when defined(pvmArm64Jit) and not defined(pvmX86Jit) and defined(pvmArmMacroStateTrace):
    f.armMacroLastState = default(ArmMacroState)
  flatClearDirty(f)
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.info = info
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.faultPage = PageAddress(0)
  f.hostCall = oracle.HostCallId(0)
  let memory = f.sourceMemory
  for page in 0..<f.sourcePages.len:
    let image = f.sourcePages[page]
    if image.access == PageAccess.Inaccessible: continue
    let address = uint64(uint32(image.index))*4096
    if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
      let offset = int(address-f.stackBase)
      flatCopySourcePage(memory, page, image, f.stack.toOpenArray(offset, offset+4095))
    elif address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
      let offset = int(address-f.rwBase)
      flatCopySourcePage(memory, page, image, f.rw.toOpenArray(offset, offset+4095))
    elif address >= f.roBase and address-f.roBase+4096 <= uint64(f.ro.len):
      let offset = int(address-f.roBase)
      flatCopySourcePage(memory, page, image, f.ro.toOpenArray(offset, offset+4095))
    else:
      var found = false
      for i in 0..<f.extra.len:
        let region {.cursor.} = f.extra[i]
        if address >= region.first and address-region.first+4096 <= uint64(region.bytes.len):
          let offset = int(address-region.first)
          flatCopySourcePage(memory, page, image, region.bytes.toOpenArray(offset, offset+4095))
          found = true
          break
      assert found

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  proc flatArmReadRegion(first: uint64, bytes: var seq[byte]): array[3, uint64] =
    ## Private region storage never resizes in place; a replacement frame rebuilds every borrowed descriptor before use.
    result = [first, 0'u64, 0'u64]
    if bytes.len >= 8:
      # Positive extent and owned storage jointly prove the native scalar's complete readable allocation.
      result[1] = uint64(bytes.len-7)
      result[2] = cast[uint64](addr bytes[0])

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  proc flatArmClippedReadRegion(first: uint64, bytes: var seq[byte]): array[3, uint64] =
    ## Intersect a moved private region with the existing eight-byte native read bounds.
    result = [0'u64, 0'u64, 0'u64]
    if bytes.len < 8: return
    let length = uint64(bytes.len)
    assert first <= 0x100000000'u64 and length <= 0x100000000'u64-first
    let extent = length-7'u64
    assert first <= high(uint64)-extent
    let endOfRegion = first+extent
    let low = max(first, 65536'u64)
    let highExclusive = min(endOfRegion, 0xfffffff8'u64)
    if highExclusive <= low: return
    let offset = low-first
    assert offset <= length-8'u64 and offset < uint64(bytes.len)
    result = [low, highExclusive-low, cast[uint64](addr bytes[int(offset)])]

  proc flatBuildArmReadContext(f: var FlatFrame) =
    ## Rebuild both tables only after the frame owns every moved private byte allocation.
    assert sizeof(ArmReadContext) == 144
    f.armMemory[0] = flatArmReadRegion(f.stackBase, f.stack)
    f.armMemory[1] = flatArmReadRegion(f.rwBase, f.rw)
    f.armMemory[2] = flatArmReadRegion(f.roBase, f.ro)
    f.armMemory[3] = flatArmClippedReadRegion(f.stackBase, f.stack)
    f.armMemory[4] = flatArmClippedReadRegion(f.rwBase, f.rw)
    f.armMemory[5] = flatArmClippedReadRegion(f.roBase, f.ro)

proc flatFrameShell[reuseDirtyMetadata: static[bool]](plan: FlatPlan, memory: Memory,
    info: MachineInfo, pageCount: int): FlatFrame =
  ## Both paths initialize every execution field afresh; the memory lease never supplies execution state.
  result = FlatFrame(plan: plan,
      preparationFailure: FlatError.None, preparationUsed: 0, hostSnapshot: default(Memory),
          hostReady: false,
    hostSnapshotPc: CodeAddress(0), fastResumes: 0, fallbackResumes: 0, hostCopiedPages: 0,
    # No store can succeed in an empty genuine map; a later host remap rebuilds this frame and its bitmap.
    dirtyPages: (when reuseDirtyMetadata: default(seq[uint64])
      else: (if pageCount == 0: @[] else: newSeq[uint64](16384))),
    dirtyIndices: (when reuseDirtyMetadata: default(seq[uint32])
      else: newSeqOfCap[uint32](pageCount)),
        info: info, reason: oracle.StepError.None,
    exit: oracle.StepExit.Continued,
    faultPage: PageAddress(0), hostCall: oracle.HostCallId(0), handlers: @[], arguments: @[],
        sites: @[],
    compiledForPc: @[], sourceMemory: memory, sourcePages: @[],
    roBase: 0, rwBase: uint64(high(uint32)), stackBase: uint64(high(uint32)), ro: @[], rw: @[],
        stack: @[], extra: @[],
    remaining: 0, reservation: 0, stoppedAt: 0, attemptedExit: false, barrier: flatStop,
        barrierFact: 0, savedHandler: nil)
  result.dynamicOffsets = default(array[256, uint64])
  when defined(pvmX86Jit):
    result.x86PreviousHeader = flatStop
    result.x86PreviousNext = flatStop
    result.x86PreviousValid = false
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    result.armPreviousHeader = flatStop
    result.armPreviousNext = flatStop
    result.armPreviousValid = false


proc buildFlatFrame(plan: FlatPlan, images: var seq[PageDescription], info: MachineInfo,
    memory: Memory): FlatFrame =
  ## Consume copied mapping metadata and read immutable page bytes directly into private resident regions.
  assert plan != nil
  # Admission already bounds the page count; also prove the exact owned snapshot allocation fits host indexing.
  assert images.len <= high(int) div sizeof(PageDescription)
  result = flatFrameShell[false](plan, memory, info, images.len)

  var regions: seq[FlatRegion] = @[]
  var first = 0
  while first < images.len:
    let image = images[first]
    if image.access == PageAccess.Inaccessible:
      # Inaccessible pages retain their original snapshot metadata without authorizing a private byte region.
      inc first
      continue
    var after = first+1
    while after < images.len and images[after].access == image.access and
        uint64(uint32(images[after].index)) == uint64(uint32(images[after-1].index))+1:
      # Only an adjacent page with the same genuine permission belongs to this allocation.
      inc after
    let pages = after-first
    assert pages > 0 and pages <= high(int) div 4096
    let address = uint64(uint32(image.index))*4096
    let region = FlatRegion(first: address, access: image.access, bytes: newSeq[byte](pages*4096))
    for page in first..<after:
      # The complete private extent is allocated once; each proven page copies exactly its original bytes.
      let offset = (page-first)*4096
      assert offset >= 0 and offset <= region.bytes.len-4096
      flatCopySourcePage(memory, page, images[page], region.bytes.toOpenArray(offset, offset+4095))
    regions.add(region)
    first = after
  # Compact metadata covers every input page; immutable source memory remains the only baseline byte owner.
  result.sourcePages = move(images)
  var firstRO = -1
  var firstRW = -1
  var lastRW = -1
  for i in 0..<regions.len:
    let region {.cursor.} = regions[i]
    if region.access == PageAccess.ReadOnly and firstRO < 0: firstRO = i
    if region.access == PageAccess.ReadWrite:
      if firstRW < 0: firstRW = i
      lastRW = i
  for i in 0..<regions.len:
    let region {.cursor.} = regions[i]
    if i == firstRO:
      result.roBase = region.first
      result.ro = move(region.bytes)
    elif i == firstRW:
      result.rwBase = region.first
      result.rw = move(region.bytes)
    elif i == lastRW:
      result.stackBase = region.first
      result.stack = move(region.bytes)
    else: result.extra.add(region)
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # Only this frame owns these byte allocations; ordinary stores/host deltas mutate bytes without reallocating them.
    flatBuildArmReadContext(result)

proc prepareFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatResult[FlatFrame] =
  ## Validate complete page admission before private region copies; a refusal contains no partial frame.
  if uint64(images.len) > uint64(uint32(plan.limits.pages)):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  let memory = captureMemory(images, plan.limits.pages)
  if memory.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  var layout = memoryLayout(memory.value)
  assert layout.error == MachineError.None
  var retained = machine.takeValue(layout)
  FlatResult[FlatFrame](status: FlatError.None, completed: buildFlatFrame(plan, retained, info, memory.value))

proc newFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatFrame =
  ## Local witness convenience only; application admission uses prepareFlatFrame and checks its typed result.
  var prepared = prepareFlatFrame(plan, images, info)
  assert prepared.error == FlatError.None
  takeValue(prepared)

func flatSourceIntervalAt(f: FlatFrame, header, maxSpan: uint32,
    found: var FlatSourceInterval): bool =
  ## A successful interval ends at a source terminal; identity, interiors and child proofs stay with callers.
  if uint64(header) >= uint64(f.handlers.len) or uint64(header) >= uint64(f.sites.len) or
      uint64(header) >= uint64(f.arguments.len): return false
  let first = f.sites[int(header)]
  let span = f.arguments[int(header)].y
  if span == 0 or span > maxSpan or uint64(first)+uint64(span) > uint64(f.plan.facts.len):
    return false
  let last = first+(span-1)
  if not f.plan.facts[int(last)].ending: return false
  # Failure leaves the output untouched; this value does not certify any handler or priced-block identity.
  found = FlatSourceInterval(first: first, last: last, span: span,
    price: f.arguments[int(header)].x)
  true

include ./handler_trace_source
when NativeCheckedReadEnabled:
  include ./handler_read_body
  include ./read_admission_probe

when defined(pvmArmMacroReceipt) or defined(pvmX86MemoryCycleSealWitness):
  func flatSourceIntervalProof*(f: FlatFrame, pc, maxSpan: uint32,
      fields: var array[5, uint64]): bool =
    ## Read only an already captured complete entry; this adapter's map proof is not the interval's contract.
    if uint64(pc) >= uint64(f.compiledForPc.len): return false
    let packed = f.compiledForPc[int(pc)]
    if packed == 0: return false
    let entry = packed-1
    if (entry and 0x80000000'u32) == 0: return false
    let header = entry and 0x7fffffff'u32
    var source = default(FlatSourceInterval)
    if not flatSourceIntervalAt(f, header, maxSpan, source): return false
    fields = [uint64(header), uint64(source.first), uint64(source.last), uint64(source.span),
      source.price]
    true

when defined(pvmX86Jit):
  proc flatX86Cycle(f: var FlatFrame, first, second: uint32, destination: var uint32): bool
    ## Cold admission is defined after exact branch-capability checking.

  proc flatX86Execute(f: var FlatFrame, offset: uint32): uint32 =
    ## Partial attempt prefixes always use the original checked node; native arithmetic has no intermediate exit.
    if f.barrier == flatStop:
      block:
        # Release the disjoint register borrow before any original fallback can mutate the frame.
        let jit {.cursor.} = f.x86Jit
        assert jit != nil
        if jit != nil:
          let ending = callX86Entry(jit, offset, f.info.registers)
          if ending != flatStop: return ending
    let original = f.x86Original[int(offset)]
    assert original != nil
    if original != nil: return original(f, offset)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatX86RunNext[ClearPaid: static[bool]](f: var FlatFrame, offset: uint32): uint32 =
    ## Only complete reserved pure prefixes enter native control; the cache borrow ends before an error can materialize frame state.
    var destination = flatStop
    block:
      let jit {.cursor.} = f.x86Jit
      assert jit != nil
      if jit != nil: destination = callX86Branch(jit, offset, f.info.registers)
    if destination == flatStop or int(destination) >= f.handlers.len:
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    when ClearPaid: f.info.blockCharged = false
    destination

  proc flatX86Branch(f: var FlatFrame, offset: uint32): uint32 =
    ## A partial source reservation must stop through original handlers, including its exact temporary barrier.
    if f.barrier != flatStop:
      let original = f.x86Original[int(offset)]
      assert original != nil
      if original != nil: return original(f, offset)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    flatX86RunNext[true](f, offset)

  proc flatX86Enter(f: var FlatFrame, offset: uint32): uint32 =
    ## Preserve canonical zero-budget, gas, resumed-block and partial-prefix ordering before the native handoff.
    flatReserve(f, offset)
    if f.barrier != flatStop:
      let selected = f.handlers[int(offset+1)]
      return selected(f, offset+1)
    block:
      let jit {.cursor.} = f.x86Jit
      assert jit != nil
      if jit != nil: inc jit.headerCalls
    flatX86RunNext[true](f, offset+1)

  proc flatX86Whole(f: var FlatFrame, offset: uint32): uint32 =
    ## A complete pure block observes neither intermediate paid state nor a source PC; every partial/resumed/error path stays checked.
    let args = f.arguments[int(offset)]
    if f.barrier != flatStop or f.info.blockCharged or f.remaining < uint64(args.y) or
        uint64(f.info.gas) < args.x:
      return flatX86Enter(f, offset)
    f.info.gas = MachineGas(uint64(f.info.gas)-args.x)
    f.remaining -= uint64(args.y)
    f.reservation = offset or flatReservationHeaderFlag
    block:
      let jit {.cursor.} = f.x86Jit
      assert jit != nil
      if jit != nil: inc jit.headerCalls
    flatX86RunNext[false](f, offset+1)

  proc flatX86ProbeWhole(f: var FlatFrame, offset: uint32): uint32 =
    ## At most eight complete visits discover an actual one/two-block round; exhaustion restores ordinary dispatch.
    let jit = f.x86Jit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    if f.pricingKind != 0 or x86RegionStatus(jit) != 0:
      if f.handlers[int(offset)] == flatX86ProbeWhole: f.handlers[int(offset)] = flatX86Whole
      return flatX86Whole(f, offset)
    let args = f.arguments[int(offset)]
    let complete = f.barrier == flatStop and not f.info.blockCharged and
        f.remaining >= uint64(args.y) and uint64(f.info.gas) >= args.x
    let destination = flatX86Whole(f, offset)
    if not complete: return destination
    let previous = f.x86PreviousHeader
    let paired = f.x86PreviousValid and f.x86PreviousNext == offset and destination == previous and
        previous != offset
    f.x86PreviousHeader = offset
    f.x86PreviousNext = destination
    f.x86PreviousValid = true
    if destination == offset or paired:
      var connected = destination
      let first = if paired: previous else: offset
      let second = if paired: offset else: flatStop
      if flatX86Cycle(f, first, second, connected): return connected
    if x86RegionStatus(jit) != 0 or x86FinishProbe(jit, offset):
      if f.handlers[int(offset)] == flatX86ProbeWhole: f.handlers[int(offset)] = flatX86Whole
    destination

  func flatX86CachedBranch(f: FlatFrame, offset: uint32): bool =
    ## Exact original worker identity certifies that both scalar destinations passed checked source/target admission.
    let opcode = f.plan.facts[int(f.sites[int(offset)])].opcode
    case opcode
    of 81: f.handlers[int(offset)] == flatBranch[81]
    of 82: f.handlers[int(offset)] == flatBranch[82]
    of 83: f.handlers[int(offset)] == flatBranch[83]
    of 84: f.handlers[int(offset)] == flatBranch[84]
    of 85: f.handlers[int(offset)] == flatBranch[85]
    of 86: f.handlers[int(offset)] == flatBranch[86]
    of 87: f.handlers[int(offset)] == flatBranch[87]
    of 88: f.handlers[int(offset)] == flatBranch[88]
    of 89: f.handlers[int(offset)] == flatBranch[89]
    of 90: f.handlers[int(offset)] == flatBranch[90]
    of 170: f.handlers[int(offset)] == flatBranch[170]
    of 171: f.handlers[int(offset)] == flatBranch[171]
    of 172: f.handlers[int(offset)] == flatBranch[172]
    of 173: f.handlers[int(offset)] == flatBranch[173]
    of 174: f.handlers[int(offset)] == flatBranch[174]
    of 175: f.handlers[int(offset)] == flatBranch[175]
    else: false

  proc flatX86Upgrade(f: var FlatFrame, offset: uint32): bool =
    ## Promote one existing arithmetic leaf only after both original branch arms have positive cached capabilities.
    let jit = f.x86Jit
    if jit == nil: return false
    let ending = x86Ending(jit, offset)
    if not flatX86CachedBranch(f, ending): return false
    let before = x86Clock()
    var native = default(X86Block)
    var current = offset
    while current < ending:
      # Rebuild only immutable pure facts already admitted by this exact source record.
      let fact = f.plan.facts[int(f.sites[int(current)])]
      emitX86Operation(native, fact.opcode, fact.args.slots, fact.args.x)
      inc current
    let args = f.arguments[int(ending)]
    let branch = f.plan.facts[int(f.sites[int(ending)])]
    emitX86Branch(native, branch.opcode, args.slots, flatSext32(uint32(args.x and 0xffffffff'u64)),
        uint32(args.x shr 32), args.y)
    let promoted = publishX86Entry(jit, offset, ending, ending-offset+1, native, conditional = true)
    jit.compilationNs += x86Clock()-before
    if not promoted:
      # A full/refused arena preserves its already working arithmetic leaf and removes repeated promotion attempts.
      f.handlers[int(offset)] = flatX86Execute
      return false
    f.handlers[int(offset)] = flatX86Branch
    if offset > 0:
      let header = offset-1
      let plain: FlatHandler = flatCharge
      if f.handlers[int(header)] == plain and
          f.sites[int(ending)]+1 == f.sites[int(header)]+f.arguments[int(header)].y:
        # Only an exact ordinary header owning this entire pure source suffix may fold its complete reservation.
        f.x86Original[int(header)] = plain
        assert f.arguments[int(header)].y > 0
        if f.pricingKind == 0 and x86RegionStatus(jit) == 0:
          x86StartProbe(jit, header)
          f.handlers[int(header)] = flatX86ProbeWhole
        else:
          f.handlers[int(header)] = flatX86Whole
    true

  proc flatX86Region(f: var FlatFrame, offset: uint32): uint32 =
    ## Every call borrows fresh state; a guard reenters the original header before that block has any effects.
    let jit = f.x86Jit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    let active = x86RegionCount(jit)
    var headers = default(array[2, uint32])
    var spans = default(array[2, uint32])
    var prices = default(array[2, uint64])
    for index in 0..<active:
      headers[index] = x86RegionHeader(jit, range[0..1](index))
      assert int(headers[index]) < f.arguments.len
      spans[index] = f.arguments[int(headers[index])].y
      prices[index] = f.arguments[int(headers[index])].x
    if f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop or
        offset != headers[0] or not x86RegionMatches(jit, headers, spans, prices):
      return flatX86Whole(f, offset)
    var state = [uint64(f.info.gas), f.remaining, 0'u64, 0'u64, uint64(flatStop)]
    let destination = callX86Region(jit, f.info.registers, state)
    f.info.gas = MachineGas(state[0])
    f.remaining = state[1]
    f.info.blockCharged = false
    if state[4] != uint64(flatStop):
      # Retain the last completed header even when the next entry returns on a quota/gas guard.
      assert state[4] < uint64(f.arguments.len)
      let last = uint32(state[4])
      f.reservation = last or flatReservationHeaderFlag
    assert int(destination) < f.handlers.len
    if int(destination) >= f.handlers.len: return flatLocal(f, offset,
        oracle.StepError.InvalidPreparedProgram)
    for index in 0..<active:
      if destination == headers[index]: return flatX86Enter(f, destination)
    destination

  proc flatX86Cycle(f: var FlatFrame, first, second: uint32, destination: var uint32): bool =
    ## Capture only complete positively resolved pure blocks; refusal retains every original source worker.
    if f.pricingKind != 0 or f.barrier != flatStop or f.info.blockCharged: return false
    let jit = f.x86Jit
    if jit == nil or x86RegionStatus(jit) == 1: return false
    if x86RegionStatus(jit) == 2:
      if x86RegionHeader(jit, 0) != first: return false
      destination = flatX86Region(f, first)
      return true
    let active: range[1..2] = if second == flatStop: 1 else: 2
    let headers = [first, second]
    let before = x86Clock()
    var blocks = default(array[2, X86RegionBlock])
    for index in 0..<active:
      let header = headers[index]
      if int(header) >= f.handlers.len: return false
      if f.handlers[int(header)] != flatX86Whole and f.handlers[int(header)] !=
          flatX86ProbeWhole: return false
      let charge = f.arguments[int(header)]
      var native = default(X86Block)
      var current = header+1
      var terminal = false
      while int(current) < f.handlers.len and current-header <= 65:
        if int(current)+1 < f.sites.len and f.sites[int(current)] == f.sites[int(
            current+1)]: return false
        let fact = f.plan.facts[int(f.sites[int(current)])]
        if fact.ending:
          if not flatX86CachedBranch(f, current) or
              f.sites[int(current)]+1 != f.sites[int(header)]+charge.y: return false
          let args = f.arguments[int(current)]
          emitX86Branch(native, fact.opcode, args.slots, flatSext32(uint32(args.x and
              0xffffffff'u64)), uint32(args.x shr 32), args.y)
          blocks[index] = X86RegionBlock(header: header, span: charge.y, operations: current-header,
              yes: uint32(args.x shr 32), no: args.y, price: charge.x, body: move(native))
          terminal = true
          break
        if not fact.fallthrough or not supportedX86Opcode(fact.opcode): return false
        emitX86Operation(native, fact.opcode, fact.args.slots, fact.args.x)
        inc current
      if not terminal: return false
    let admitted = publishX86Region(jit, blocks, active)
    jit.compilationNs += x86Clock()-before
    if not admitted: return false
    f.handlers[int(first)] = flatX86Region
    destination = flatX86Region(f, first)
    true

  proc flatX86RegionStatistics*(f: FlatFrame): array[2, uint64] =
    ## A witness requires real connected execution separately from normal arithmetic/conditional leaves.
    let jit = f.x86Jit
    if jit == nil: default(array[2, uint64])
    else: x86RegionStatistics(jit)

  proc flatX86Pending(f: var FlatFrame, offset: uint32): uint32 =
    ## Original first execution admits both branch arms; only a later full reservation may promote native control.
    if f.barrier == flatStop and flatX86Upgrade(f, offset): return flatX86Branch(f, offset)
    flatX86Execute(f, offset)

  proc flatX86Prepare(f: var FlatFrame, origin: uint32) =
    ## Compile bounded same-block pure spans only, leaving pricing, branches, memory, hosts and faults checked.
    if not f.plan.allowNative: return
    let before = x86Clock()
    if f.x86Jit == nil: f.x86Jit = newX86Jit()
    let jit = f.x86Jit
    assert jit != nil
    if jit == nil: return
    var offset = origin
    while int(offset) < f.handlers.len:
      # Duplicate source sites are synthetic charge headers and never authorize native source operations.
      if x86Entry(jit, offset, uint32(f.handlers.len)) != 0 or
          (int(offset)+1 < f.sites.len and f.sites[int(offset)] == f.sites[int(offset+1)]):
        inc offset
        continue
      var ending = offset
      var count = 0'u32
      var fragment = default(X86Block)
      while int(ending) < f.handlers.len and count < 64:
        if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending+1)]: break
        let fact = f.plan.facts[int(f.sites[int(ending)])]
        if fact.ending or not fact.fallthrough or not supportedX86Opcode(fact.opcode): break
        emitX86Operation(fragment, fact.opcode, fact.args.slots, fact.args.x)
        inc ending
        inc count
      let terminal = if int(ending) < f.sites.len:
          f.plan.facts[int(f.sites[int(ending)])].opcode else: 0'u8
      let conditional = terminal in {81'u8..90, 170..175}
      var whole = false
      if conditional and offset > 0 and int(ending) < f.sites.len:
        # Short native handoffs pay off only with a complete ordinary charge entry; interior prefixes retain fused checked workers.
        let header = offset-1
        let plain: FlatHandler = flatCharge
        whole = f.handlers[int(header)] == plain and
            f.sites[int(ending)]+1 == f.sites[int(header)]+f.arguments[int(header)].y
      if count == 0 or (count < 4 and not whole) or
          not publishX86Entry(jit, offset, ending, count, fragment, shortPrefix = whole):
        refuseX86Entry(jit, offset)
        inc offset
        continue
      if f.x86Original.len < f.handlers.len: f.x86Original.setLen(f.handlers.len)
      f.x86Original[int(offset)] = f.handlers[int(offset)]
      f.handlers[int(offset)] = if conditional: flatX86Pending else: flatX86Execute
      offset = ending
    jit.compilationNs += x86Clock()-before

  when defined(pvmX86Jit) or defined(pvmX86MemoryCycleSeal):
    func flatX86CompleteSource(f: FlatFrame, pc: uint32,
        found: var X86MemoryCycleHeader): bool =
      ## Recheck one published basic-block header, its original priced span and every emitted site.
      found = default(X86MemoryCycleHeader)
      var header = 0'u32
      var source = default(FlatSourceInterval)
      if not flatCompleteOriginalHeader(f, pc, 65, header, source): return false
      let ordinal = source.first
      let last = source.last
      var summary = default(FlatSourceSummary)
      if not flatWalkCompleteSource(f, header, source, summary): return false
      let handler = f.handlers[int(header)]
      let kind = if handler == flatCharge: X86MemoryCycleHandlerKind.Ordinary
        elif handler == flatChargedWordLoop: X86MemoryCycleHandlerKind.CheckedWord
        elif handler == flatX86Whole: X86MemoryCycleHandlerKind.NativeWhole
        elif handler == flatX86ProbeWhole: X86MemoryCycleHandlerKind.NativeProbe
        elif handler == flatX86Region: X86MemoryCycleHandlerKind.NativeRegion
        else: X86MemoryCycleHandlerKind.Other
      found = X86MemoryCycleHeader(pc: pc, header: header, ordinal: ordinal, span: source.span,
        terminal: summary.terminal, price: source.price,
        opcode: f.plan.facts[int(last)].opcode, kind: kind)
      true

    func flatX86CompleteTarget(f: FlatFrame, offset: uint32,
        found: var X86MemoryCycleHeader): bool =
      ## A cached arm must name the exact current complete header, never an interior or stale site.
      found = default(X86MemoryCycleHeader)
      if int(offset) >= f.sites.len: return false
      let ordinal = f.sites[int(offset)]
      if int(ordinal) >= f.plan.facts.len: return false
      let pc = f.plan.facts[int(ordinal)].pc
      flatX86CompleteSource(f, pc, found) and found.header == offset

    func flatX86SealMemoryCycle*(f: FlatFrame, prefixPc: uint32,
        candidate: var X86MemoryCycleCandidate): bool =
      ## Prove the narrow three-block source graph without reading guest values or changing a cache.
      candidate = default(X86MemoryCycleCandidate)
      # This is a source-only seal. A stopped paid frame may publish code because the worker
      # retains the original handler for every paid or partial-budget reentry.
      # The publisher separately requires an executable owner, even when this source is valid.
      if not f.plan.allowNative or f.plan.singleStep or f.preparationFailure != FlatError.None or
          f.pricingKind != 0 or f.barrier != flatStop:
        return false
      var prefix = default(X86MemoryCycleHeader)
      if not flatX86CompleteSource(f, prefixPc, prefix): return false
      if prefix.kind notin {X86MemoryCycleHandlerKind.Ordinary,
          X86MemoryCycleHandlerKind.NativeWhole, X86MemoryCycleHandlerKind.NativeProbe,
          X86MemoryCycleHandlerKind.NativeRegion} or
          prefix.opcode != 1 or
          f.handlers[int(prefix.terminal)] != flatCachedJump[1]: return false
      var dirty = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, f.arguments[int(prefix.terminal)].y, dirty): return false
      if prefix.header == dirty.header or dirty.span != 5 or dirty.opcode != 171 or
          dirty.kind != X86MemoryCycleHandlerKind.CheckedWord or
          not flatX86CachedBranch(f, dirty.terminal): return false
      for i in 0..<5:
        if f.plan.facts[int(dirty.ordinal)+i].opcode != [198'u8, 120, 149, 149, 171][i]:
          return false
      if not flatWordShape(f, dirty.header): return false
      let dirtyArms = f.arguments[int(dirty.terminal)]
      if uint32(dirtyArms.x shr 32) != dirty.header: return false
      dirty.yes = dirty.header
      var tail = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, dirtyArms.y, tail): return false
      if tail.header == prefix.header or tail.header == dirty.header or
          tail.kind != X86MemoryCycleHandlerKind.Ordinary or tail.opcode != 173 or
          not flatX86CachedBranch(f, tail.terminal): return false
      var prefixOps = default(array[4, uint32])
      var prefixCount = 0
      for at in prefix.ordinal..<prefix.ordinal+prefix.span:
        if f.plan.facts[int(at)].opcode != 2:
          if prefixCount >= prefixOps.len: return false
          prefixOps[prefixCount] = at
          inc prefixCount
      if prefixCount != 4 or f.plan.facts[int(prefixOps[0])].opcode != 51 or
          f.plan.facts[int(prefixOps[1])].opcode != 200 or
          f.plan.facts[int(prefixOps[2])].opcode != 149 or
          f.plan.facts[int(prefixOps[3])].opcode != 1: return false
      var tailOps = default(array[3, uint32])
      var tailCount = 0
      for at in tail.ordinal..<tail.ordinal+tail.span:
        if f.plan.facts[int(at)].opcode != 2:
          if tailCount >= tailOps.len: return false
          tailOps[tailCount] = at
          inc tailCount
      if tailCount != 3 or f.plan.facts[int(tailOps[0])].opcode notin {52'u8..58} or
          f.plan.facts[int(tailOps[1])].opcode != 131 or
          f.plan.facts[int(tailOps[2])].opcode != 173: return false
      let tailArms = f.arguments[int(tail.terminal)]
      if uint32(tailArms.x shr 32) != prefix.header: return false
      tail.yes = prefix.header
      var outside = default(X86MemoryCycleHeader)
      if not flatX86CompleteTarget(f, tailArms.y, outside): return false
      if outside.header == prefix.header or outside.header == dirty.header or
          outside.header == tail.header or outside.kind != X86MemoryCycleHandlerKind.Ordinary:
        return false
      dirty.no = tail.header
      tail.no = outside.header
      prefix.yes = dirty.header
      let pLoad = f.arguments[int(prefix.header+1)]
      let pBound = f.arguments[int(prefix.header+2)]
      let pStep = f.arguments[int(prefix.header+3)]
      let dExtract = f.arguments[int(dirty.header+1)]
      let dStore = f.arguments[int(dirty.header+2)]
      let dBranch = f.arguments[int(dirty.terminal)]
      let tRead = f.arguments[int(tail.header+1)]
      let tStep = f.arguments[int(tail.header+2)]
      let tBranch = f.arguments[int(tail.terminal)]
      let data = dExtract.slots.aIndex
      let shift = dExtract.slots.bIndex
      let extracted = dExtract.slots.destinationIndex
      let base = dStore.slots.bIndex
      let bound = dBranch.slots.bIndex
      let length = pBound.slots.bIndex
      let counter = tBranch.slots.aIndex
      let readResult = tRead.slots.aIndex
      let roles = [data, shift, extracted, base, bound, length, counter, readResult]
      for i in 0..<roles.len:
        for j in i+1..<roles.len:
          if roles[i] == roles[j]: return false
      if pLoad.slots.destinationIndex != shift or pBound.slots.aIndex != base or
          pBound.slots.destinationIndex != bound or pStep.slots.bIndex != bound or
          pStep.slots.destinationIndex != bound or pStep.x != 1 or
          tStep.slots.bIndex != counter or tStep.slots.destinationIndex != counter or
          tStep.x != 1 or tBranch.slots.bIndex != readResult: return false
      let readOpcode = f.plan.facts[int(tailOps[0])].opcode
      let width = case readOpcode
        of 52, 53: 1'u8
        of 54, 55: 2'u8
        of 56, 57: 4'u8
        else: 8'u8
      candidate = X86MemoryCycleCandidate(prefix: prefix, dirty: dirty, tail: tail,
        outside: outside, readOrdinal: tailOps[0], readImmediate: tRead.x,
        storeDisplacement: dStore.x, initialShift: pLoad.x,
        readOpcode: readOpcode, readWidth: width,
        data: byte(data), shift: byte(shift), extracted: byte(extracted), base: byte(base),
        bound: byte(bound), length: byte(length), counter: byte(counter),
        readResult: byte(readResult))
      true

    when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
      func flatX86WideReadBlock(f: FlatFrame, header: uint32,
          cycle: X86MemoryCycleCandidate, found: var X86MemoryCycleHeader,
          operations, loads: var uint32): bool =
        ## A complete original block contains only speculative reads and pure scalar operations.
        found = default(X86MemoryCycleHeader)
        operations = 0
        loads = 0
        if not flatX86CompleteTarget(f, header, found) or
            found.kind != X86MemoryCycleHandlerKind.Ordinary or
            found.opcode != 1 or found.span < 4 or found.span > 65 or
            f.handlers[int(found.terminal)] != flatCachedJump[1] or
            f.arguments[int(found.terminal)].y != cycle.prefix.header:
          return false
        if f.plan.facts[int(found.ordinal)].opcode != 2 or
            f.plan.facts[int(found.ordinal)+1].opcode notin
              {52'u8..58'u8, 124'u8..130'u8}:
          return false
        for ordinal in found.ordinal+1..<found.ordinal+found.span-1:
          let fact = f.plan.facts[int(ordinal)]
          if fact.opcode == 2 or fact.ending or not fact.fallthrough:
            return false
          if fact.opcode in {52'u8..58'u8, 124'u8..130'u8}:
            inc loads
          elif not supportedX86Opcode(fact.opcode):
            return false
          inc operations
        operations >= 4 and operations <= 64 and loads >= 2 and loads <= 16

      func flatX86WideBranch(f: FlatFrame, header: uint32,
          guard: X86MemoryCycleHeader, cycle: X86MemoryCycleCandidate,
          found, readBlock: var X86MemoryCycleHeader,
          operations, loads: var uint32): bool =
        ## Both cached arms are positive source targets; exactly one returns to the outer guard.
        found = default(X86MemoryCycleHeader)
        readBlock = default(X86MemoryCycleHeader)
        operations = 0
        loads = 0
        if not flatX86CompleteTarget(f, header, found) or
            found.kind != X86MemoryCycleHandlerKind.Ordinary or found.span != 1 or
            found.opcode != 88 or not flatX86CachedBranch(f, found.terminal):
          return false
        let arms = f.arguments[int(found.terminal)]
        let yes = uint32(arms.x shr 32)
        let no = arms.y
        if yes == no or (yes == guard.header) == (no == guard.header): return false
        let readHeader = if yes == guard.header: no else: yes
        if not flatX86WideReadBlock(f, readHeader, cycle, readBlock, operations, loads):
          return false
        found.yes = yes
        found.no = no
        true

      func flatX86SealWideCycle*(f: FlatFrame, prefixPc: uint32,
          candidate: var X86WideCycleCandidate): bool =
        ## Derive seven current complete blocks from positive cached edges, never from a fixture PC.
        candidate = default(X86WideCycleCandidate)
        var cycle = default(X86MemoryCycleCandidate)
        if not flatX86SealMemoryCycle(f, prefixPc, cycle): return false
        let outside = cycle.outside
        if outside.kind != X86MemoryCycleHandlerKind.Ordinary or outside.span != 1 or
            outside.opcode != 40 or
            f.handlers[int(outside.terminal)] != flatCachedJump[40]: return false
        var guard = default(X86MemoryCycleHeader)
        if not flatX86CompleteTarget(f, f.arguments[int(outside.terminal)].y, guard) or
            guard.span != 3 or guard.opcode != 81 or
            guard.kind notin {X86MemoryCycleHandlerKind.Ordinary,
              X86MemoryCycleHandlerKind.NativeWhole,
              X86MemoryCycleHandlerKind.NativeProbe,
              X86MemoryCycleHandlerKind.NativeRegion} or
            not flatX86CachedBranch(f, guard.terminal): return false
        for index, opcode in [131'u8, 149, 81]:
          if f.plan.facts[int(guard.ordinal)+index].opcode != opcode: return false
        let arms = f.arguments[int(guard.terminal)]
        let yes = uint32(arms.x shr 32)
        let no = arms.y
        if yes == no: return false
        var branch = default(X86MemoryCycleHeader)
        var readBlock = default(X86MemoryCycleHeader)
        var rare = default(X86MemoryCycleHeader)
        var operations = 0'u32
        var loads = 0'u32
        var found = 0
        for target in [yes, no]:
          var trialBranch = default(X86MemoryCycleHeader)
          var trialRead = default(X86MemoryCycleHeader)
          var trialOperations = 0'u32
          var trialLoads = 0'u32
          if flatX86WideBranch(f, target, guard, cycle, trialBranch, trialRead,
              trialOperations, trialLoads):
            inc found
            branch = trialBranch
            readBlock = trialRead
            operations = trialOperations
            loads = trialLoads
        if found != 1: return false
        let rareTarget = if yes == branch.header: no else: yes
        if not flatX86CompleteTarget(f, rareTarget, rare): return false
        guard.yes = yes
        guard.no = no
        let headers = [cycle.prefix.header, cycle.dirty.header, cycle.tail.header,
          outside.header, guard.header, branch.header, readBlock.header]
        for index in 0..<headers.len:
          if headers[index] == rare.header: return false
          for earlier in 0..<index:
            if headers[index] == headers[earlier]: return false
        candidate = X86WideCycleCandidate(cycle: cycle, loopGuard: guard,
          loopBranch: branch, readBlock: readBlock, rare: rare,
          readOperations: operations, readLoads: loads)
        true

      func flatX86WideEmission(f: FlatFrame, candidate: X86WideCycleCandidate,
          emission: var X86WideEmission): bool =
        ## Copy only the sealed source operands; generated code receives no frame reference.
        emission = default(X86WideEmission)
        emission.prefix = flatX86CycleEmission(f, candidate.cycle)
        let guard = candidate.loopGuard
        if guard.span != 3 or guard.terminal != guard.header+3: return false
        for index in 0..<2:
          let fact = f.plan.facts[int(guard.ordinal)+index]
          if not supportedX86Opcode(fact.opcode): return false
          emission.guardOperations[index] = X86WideOperation(opcode: fact.opcode,
            slots: fact.args.slots, immediate: fact.args.x)
        let guardBranch = f.arguments[int(guard.terminal)]
        emission.guardBranch = guardBranch.slots
        emission.guardImmediate = flatSext32(uint32(guardBranch.x and 0xffffffff'u64))
        let loopBranch = f.arguments[int(candidate.loopBranch.terminal)]
        emission.loopBranch = loopBranch.slots
        emission.loopImmediate = flatSext32(uint32(loopBranch.x and 0xffffffff'u64))
        var count = 0'u32
        for current in candidate.readBlock.header+1..<candidate.readBlock.terminal:
          if int(current) >= f.sites.len: return false
          let fact = f.plan.facts[int(f.sites[int(current)])]
          if fact.opcode notin {52'u8..58'u8, 124'u8..130'u8} and
              not supportedX86Opcode(fact.opcode): return false
          if count >= uint32(emission.readOperations.len): return false
          emission.readOperations[int(count)] = X86WideOperation(opcode: fact.opcode,
            slots: fact.args.slots, immediate: fact.args.x)
          inc count
        if count != candidate.readOperations: return false
        emission.readCount = count
        true

    when defined(pvmX86MemoryCycleSealWitness):
      func flatX86CompleteTargetWitness*(f: FlatFrame, offset: uint32): bool =
        ## Recheck an observed scalar destination without resolving it or changing its source owner.
        var found = default(X86MemoryCycleHeader)
        flatX86CompleteTarget(f, offset, found)

      func flatX86InteriorSourceWitness*(f: FlatFrame, pc: uint32): bool =
        ## A present interior coordinate has no complete-header authority for a source seal.
        if int(pc) >= f.compiledForPc.len: return false
        let packed = f.compiledForPc[int(pc)]
        packed != 0 and ((packed-1) and 0x80000000'u32) == 0

      func flatX86UncachedTailWitness*(f: FlatFrame, pc: uint32): bool =
        ## A complete tail may exist before its original conditional acquires both cached arms.
        var tail = default(X86MemoryCycleHeader)
        flatX86CompleteSource(f, pc, tail) and not flatX86CachedBranch(f, tail.terminal)

      proc flatX86BarrierRefusalWitness*(f: var FlatFrame, prefixPc: uint32): bool =
        ## A test-only idle barrier proves refusal and restores the exact original frame scalar.
        let original = f.barrier
        f.barrier = 0
        var candidate = default(X86MemoryCycleCandidate)
        result = not flatX86SealMemoryCycle(f, prefixPc, candidate)
        f.barrier = original

  when defined(pvmX86Jit) or (defined(pvmX86MemoryCycleNativeProof) and
      defined(pvmX86MemoryCycleSeal)):
    proc flatX86CycleAbort() {.cdecl, importc: "abort", header: "stdlib.h".}
      ## An impossible post-native receipt cannot be rolled back or replayed through checked code.

    func flatX86CyclePrefixMatches(f: FlatFrame, candidate: X86MemoryCycleCandidate): bool =
      ## A cheap exact handler-class check retires persistent pure promotions without rescanning source.
      let header = candidate.prefix.header
      if int(header) >= f.handlers.len: return false
      let handler = f.handlers[int(header)]
      case candidate.prefix.kind
      of X86MemoryCycleHandlerKind.Ordinary: handler == flatCharge
      of X86MemoryCycleHandlerKind.NativeWhole: handler == flatX86Whole
      of X86MemoryCycleHandlerKind.NativeProbe: handler == flatX86ProbeWhole
      of X86MemoryCycleHandlerKind.NativeRegion: handler == flatX86Region
      else: false

    proc flatX86CycleReadRegion(first: uint64, bytes: var seq[byte], address: uint64,
        width: uint8, memory: var X86CycleMemory) =
      ## A current private region supplies one clipped address interval, or no native read capability.
      if bytes.len == 0 or first > uint64(high(uint32))+1 or
          uint64(bytes.len) > uint64(high(uint32))+1-first: return
      let ending = first+uint64(bytes.len)
      if address < first or address > high(uint64)-uint64(width) or
          address+uint64(width) > ending: return
      memory.readPtr = addr bytes[0]
      memory.readFirst = first
      memory.readEnd = ending

    proc flatX86CycleWriteRegion(first: uint64, bytes: var seq[byte], address: uint64,
        memory: var X86CycleMemory) =
      ## One complete writable four-byte extent is selected before any native store can occur.
      if bytes.len < 4 or first > uint64(high(uint32))+1 or
          uint64(bytes.len) > uint64(high(uint32))+1-first: return
      let ending = first+uint64(bytes.len)
      if address < first or address > high(uint64)-4 or address+4 > ending: return
      memory.writePtr = addr bytes[0]
      memory.writeFirst = first
      memory.writeEnd = ending

    proc flatX86CycleMemory(f: var FlatFrame, candidate: X86MemoryCycleCandidate):
        X86CycleMemory =
      ## Reborrow private memory on each call; no pointer follows the cache through a move or host remap.
      result = default(X86CycleMemory)
      if candidate.base > 12: return
      let base = uint64(f.info.registers[range[0..12](candidate.base)])
      let writeAddress = (base+candidate.storeDisplacement) and 0xffffffff'u64
      flatX86CycleWriteRegion(f.stackBase, f.stack, writeAddress, result)
      if result.writePtr == nil:
        flatX86CycleWriteRegion(f.rwBase, f.rw, writeAddress, result)
      let readAddress = candidate.readImmediate and 0xffffffff'u64
      flatX86CycleReadRegion(f.stackBase, f.stack, readAddress, candidate.readWidth, result)
      if result.readPtr == nil:
        flatX86CycleReadRegion(f.rwBase, f.rw, readAddress, candidate.readWidth, result)
      if result.readPtr == nil:
        flatX86CycleReadRegion(f.roBase, f.ro, readAddress, candidate.readWidth, result)
      assert f.dirtyPages.len <= int(high(uint32))
      result.dirtyWords = uint32(f.dirtyPages.len)

    func flatX86CycleReceiptValid(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32): bool =
      ## Validate every equation and allowed completed/next edge before publishing frame bookkeeping.
      if state.reserved != 0 or state.gas > startGas or state.attempts > startAttempts or
          (state.exitKind != 1 and state.exitKind != 2): return false
      let spentGas = startGas-state.gas
      let spentAttempts = startAttempts-state.attempts
      if state.wordGroups > high(uint64) div 4 or
          state.visits[1] != state.wordGroups*4: return false
      let spans = [candidate.prefix.span, candidate.dirty.span, candidate.tail.span]
      let prices = [candidate.prefix.price, candidate.dirty.price, candidate.tail.price]
      var countedGas = 0'u64
      var countedAttempts = 0'u64
      var visitsTotal = 0'u64
      for index in 0..<3:
        let visits = state.visits[index]
        let span = uint64(spans[index])
        let price = prices[index]
        if span == 0 or visits > (spentAttempts-countedAttempts) div span: return false
        countedAttempts += visits*span
        if price != 0:
          if visits > (spentGas-countedGas) div price: return false
          countedGas += visits*price
        if visits > high(uint64)-visitsTotal: return false
        visitsTotal += visits
      if countedGas != spentGas or countedAttempts != spentAttempts or
          (state.lastCompleted == high(uint32)) != (visitsTotal == 0): return false
      # Every tail follows one completed word group, and every prefix follows one tail.
      if state.visits[2] > state.wordGroups or state.visits[0] > state.visits[2] or
          state.visits[2]-state.visits[0] > 1: return false
      let openTail = state.visits[2]-state.visits[0]
      # A dirty completion after a prefix needs a fresh group, even when earlier counts balance.
      if state.lastCompleted == candidate.dirty.header and
          state.wordGroups <= state.visits[0]: return false
      if state.exitKind == 2:
        return openTail == 1 and next == candidate.outside.header and
          state.lastCompleted == candidate.tail.header and state.visits[2] > 0
      if next == candidate.dirty.header:
        return openTail == 0 and (state.lastCompleted == high(uint32) or
          (state.lastCompleted == candidate.dirty.header and state.visits[1] > 0) or
          (state.lastCompleted == candidate.prefix.header and state.visits[0] > 0))
      if next == candidate.tail.header:
        return openTail == 0 and state.lastCompleted == candidate.dirty.header and
          state.visits[1] > 0
      if next == candidate.prefix.header:
        return openTail == 1 and state.lastCompleted == candidate.tail.header and
          state.visits[2] > 0
      false

    func flatX86CycleEmission(f: FlatFrame, candidate: X86MemoryCycleCandidate):
        X86CycleEmission =
      ## Copy only the original sealed operand slots used by the arithmetic/branch emitter.
      X86CycleEmission(
        prefixLoad: f.arguments[int(candidate.prefix.header+1)].slots,
        prefixBound: f.arguments[int(candidate.prefix.header+2)].slots,
        prefixStep: f.arguments[int(candidate.prefix.header+3)].slots,
        dirtyBranch: f.arguments[int(candidate.dirty.terminal)].slots,
        tailStep: f.arguments[int(candidate.tail.header+2)].slots,
        tailBranch: f.arguments[int(candidate.tail.terminal)].slots)

    proc flatX86CycleWorker(f: var FlatFrame, offset: uint32): uint32 =
      ## Only the explicit proof installer can make this checked dirty-header wrapper reachable.
      let saved = if int(offset) < f.x86Original.len: f.x86Original[int(offset)] else: nil
      if saved == nil: flatX86CycleAbort(); return flatStop
      let jit = f.x86Jit
      if jit == nil: return saved(f, offset)
      let slot = x86CycleSlot(jit, offset)
      if slot < 0: return saved(f, offset)
      let candidate = x86CycleCandidate(jit, slot)
      if f.plan == nil or not x86CycleBound(jit, slot, cast[pointer](f.plan)):
        flatX86CycleAbort()
        return flatStop
      if f.preparationFailure != FlatError.None or not f.plan.allowNative or
          f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop:
        return saved(f, offset)
      if int(candidate.tail.header) >= f.handlers.len or
          int(candidate.outside.header) >= f.handlers.len or
          f.handlers[int(offset)] != flatX86CycleWorker or
          not flatX86CyclePrefixMatches(f, candidate) or
          f.handlers[int(candidate.tail.header)] != flatCharge or
          f.handlers[int(candidate.outside.header)] != flatCharge:
        # A persistent handler promotion only retires this optimization, preserving its pure region.
        retireX86Cycle(jit, slot)
        if f.handlers[int(offset)] == flatX86CycleWorker: f.handlers[int(offset)] = saved
        return saved(f, offset)
      var memory = flatX86CycleMemory(f, candidate)
      if memory.writePtr == nil: return saved(f, offset)
      var state = X86CycleState(gas: uint64(f.info.gas), attempts: f.remaining,
        visits: [0'u64, 0'u64, 0'u64], wordGroups: 0, lastCompleted: high(uint32),
        exitKind: 0, reserved: 0)
      let startGas = state.gas
      let startAttempts = state.attempts
      let receipt = callX86MemoryCycle(jit, slot, f.info.registers, memory, f.dirtyPages, state)
      if receipt == 0: return saved(f, offset) # C refused before invoking any native byte.
      if receipt shr 32 != 1: flatX86CycleAbort(); return flatStop
      let next = uint32(receipt and 0xffffffff'u64)
      if not flatX86CycleReceiptValid(candidate, startGas, startAttempts, state, next):
        flatX86CycleAbort()
        return flatStop
      if not recordX86MemoryCycle(jit, state.visits[0], state.visits[1],
          state.visits[2], state.wordGroups): flatX86CycleAbort(); return flatStop
      f.info.gas = MachineGas(state.gas)
      f.remaining = state.attempts
      if state.lastCompleted != high(uint32):
        let completed = if state.lastCompleted == candidate.prefix.header: candidate.prefix
          elif state.lastCompleted == candidate.dirty.header: candidate.dirty
          else: candidate.tail
        f.stoppedAt = completed.terminal
        f.reservation = completed.header or flatReservationHeaderFlag
        f.attemptedExit = false
        f.info.blockCharged = false
        f.barrier = flatStop
      if state.exitKind == 2: return next
      if next == offset: return saved(f, offset)
      let selected = f.handlers[int(next)]
      selected(f, next)

    when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
      proc flatX86WideMemory(f: var FlatFrame,
          candidate: X86WideCycleCandidate): X86WideMemory =
        ## Borrow only complete immutable extents for one call; extra/fragmented reads replay.
        result = default(X86WideMemory)
        result.cycle = flatX86CycleMemory(f, candidate.cycle)
        if f.stackBase <= f.rwBase or f.rwBase <= f.roBase: return
        let ceiling = uint64(high(uint32))+1'u64
        if f.stackBase > ceiling or uint64(f.stack.len) > ceiling-f.stackBase or
            f.rwBase > ceiling or uint64(f.rw.len) > ceiling-f.rwBase or
            f.roBase > ceiling or uint64(f.ro.len) > ceiling-f.roBase: return
        result.regions[0].first = f.stackBase
        result.regions[0].ending = f.stackBase+uint64(f.stack.len)
        if f.stack.len > 0: result.regions[0].data = addr f.stack[0]
        result.regions[1].first = f.rwBase
        result.regions[1].ending = f.rwBase+uint64(f.rw.len)
        if f.rw.len > 0: result.regions[1].data = addr f.rw[0]
        result.regions[2].first = f.roBase
        result.regions[2].ending = f.roBase+uint64(f.ro.len)
        if f.ro.len > 0: result.regions[2].data = addr f.ro[0]

      func flatX86WideReceiptValid(candidate: X86WideCycleCandidate, startGas,
          startAttempts: uint64, state: X86WideState, next: uint32): bool =
        ## Exact charged/completed equations include a speculative read charged before replay.
        let cycle = state.cycle
        let outsideVisits = state.outerVisits[0]
        let guardVisits = state.outerVisits[1]
        let branchVisits = state.outerVisits[2]
        let readVisits = state.outerVisits[3]
        if cycle.reserved != 0 or cycle.gas > startGas or
            cycle.attempts > startAttempts or
            (cycle.exitKind != 1 and cycle.exitKind != 2 and cycle.exitKind != 3) or
            cycle.wordGroups > high(uint64) div 4 or
            cycle.visits[1] != cycle.wordGroups*4 or
            cycle.visits[2] > cycle.wordGroups or
            cycle.visits[0] < state.childCalls or
            state.childCalls > readVisits or
            readVisits-state.childCalls > 1 or
            outsideVisits > state.childCalls or
            state.childCalls-outsideVisits > 1 or
            readVisits > branchVisits or
            guardVisits > branchVisits: return false
        # Branch chooses either guard directly or read→child→outside→guard.
        # Only one branch/read/child segment can remain open at a return.
        let openBranches = branchVisits-guardVisits
        if openBranches > 1 or readVisits-outsideVisits > openBranches:
          return false
        if cycle.visits[2] > high(uint64)-state.childCalls: return false
        let childTails = cycle.visits[2]+state.childCalls
        if cycle.visits[0] > childTails: return false
        let openTails = childTails-cycle.visits[0]
        if openTails < state.outerVisits[0] or
            openTails-state.outerVisits[0] > 1:
          return false
        let spans = [candidate.cycle.prefix.span, candidate.cycle.dirty.span,
          candidate.cycle.tail.span, candidate.cycle.outside.span,
          candidate.loopGuard.span, candidate.loopBranch.span,
          candidate.readBlock.span]
        let prices = [candidate.cycle.prefix.price, candidate.cycle.dirty.price,
          candidate.cycle.tail.price, candidate.cycle.outside.price,
          candidate.loopGuard.price, candidate.loopBranch.price,
          candidate.readBlock.price]
        let visits = [cycle.visits[0], cycle.visits[1], cycle.visits[2],
          state.outerVisits[0], state.outerVisits[1], state.outerVisits[2],
          state.outerVisits[3]]
        var countedGas = 0'u64
        var countedAttempts = 0'u64
        var completed = 0'u64
        for index in 0..<visits.len:
          let count = visits[index]
          if count > high(uint64)-completed: return false
          completed += count
          if count > 0 and uint64(spans[index]) > high(uint64) div count:
            return false
          let attempts = count*uint64(spans[index])
          if attempts > high(uint64)-countedAttempts: return false
          countedAttempts += attempts
          if prices[index] != 0 and count > high(uint64) div prices[index]:
            return false
          let gas = count*prices[index]
          if gas > high(uint64)-countedGas: return false
          countedGas += gas
        if cycle.exitKind == 3:
          if countedAttempts > high(uint64)-uint64(candidate.readBlock.span) or
              countedGas > high(uint64)-candidate.readBlock.price: return false
          countedAttempts += uint64(candidate.readBlock.span)
          countedGas += candidate.readBlock.price
        if countedGas != startGas-cycle.gas or
            countedAttempts != startAttempts-cycle.attempts or
            (cycle.lastCompleted == high(uint32)) != (completed == 0): return false
        let known = [candidate.cycle.prefix.header, candidate.cycle.dirty.header,
          candidate.cycle.tail.header, candidate.cycle.outside.header,
          candidate.loopGuard.header, candidate.loopBranch.header,
          candidate.readBlock.header]
        if completed > 0 and cycle.lastCompleted notin known: return false
        if cycle.exitKind == 2:
          return next == candidate.rare.header and
            cycle.lastCompleted == candidate.loopGuard.header and
            openBranches == 0 and readVisits == outsideVisits
        if cycle.exitKind == 3:
          return next == candidate.readBlock.header+1 and
            cycle.lastCompleted == candidate.loopBranch.header and
            state.childCalls == readVisits and openBranches == 1 and
            readVisits == outsideVisits
        if next == candidate.loopBranch.header:
          return openBranches == 0 and readVisits == outsideVisits
        if next == candidate.loopGuard.header or
            next == candidate.readBlock.header:
          return openBranches == 1 and readVisits == outsideVisits
        if next in [candidate.cycle.prefix.header, candidate.cycle.dirty.header,
            candidate.cycle.tail.header, candidate.cycle.outside.header]:
          return openBranches == 1 and readVisits-outsideVisits == 1
        false

      func flatX86WideMatches(f: FlatFrame,
          candidate: X86WideCycleCandidate): bool =
        ## Immutable plan identity plus current charges/positive arms retire any stale stream view.
        let cycle = candidate.cycle
        let headers = [cycle.prefix, cycle.dirty, cycle.tail, cycle.outside,
          candidate.loopGuard, candidate.loopBranch, candidate.readBlock]
        for header in headers:
          if int(header.header) >= f.arguments.len or
              int(header.terminal) >= f.arguments.len or
              f.arguments[int(header.header)].x != header.price or
              f.arguments[int(header.header)].y != header.span: return false
        if not flatX86CyclePrefixMatches(f, cycle) or
            f.handlers[int(cycle.dirty.header)] != flatX86CycleWorker or
            f.handlers[int(cycle.tail.header)] != flatCharge or
            f.handlers[int(cycle.outside.header)] != flatCharge or
            f.handlers[int(candidate.readBlock.header)] != flatCharge or
            f.handlers[int(candidate.loopBranch.header)] != flatX86WideWorker or
            f.handlers[int(cycle.outside.terminal)] != flatCachedJump[40] or
            f.handlers[int(candidate.loopGuard.terminal)] != flatBranch[81] or
            f.handlers[int(candidate.loopBranch.terminal)] != flatBranch[88] or
            f.handlers[int(candidate.readBlock.terminal)] != flatCachedJump[1]:
          return false
        let guard = f.handlers[int(candidate.loopGuard.header)]
        case candidate.loopGuard.kind
        of X86MemoryCycleHandlerKind.Ordinary:
          if guard != flatCharge: return false
        of X86MemoryCycleHandlerKind.NativeWhole:
          if guard != flatX86Whole: return false
        of X86MemoryCycleHandlerKind.NativeProbe:
          if guard != flatX86ProbeWhole: return false
        of X86MemoryCycleHandlerKind.NativeRegion:
          if guard != flatX86Region: return false
        else: return false
        let outside = f.arguments[int(cycle.outside.terminal)]
        let guardArms = f.arguments[int(candidate.loopGuard.terminal)]
        let branchArms = f.arguments[int(candidate.loopBranch.terminal)]
        let readTarget = f.arguments[int(candidate.readBlock.terminal)]
        outside.y == candidate.loopGuard.header and
          uint32(guardArms.x shr 32) == candidate.loopGuard.yes and
          guardArms.y == candidate.loopGuard.no and
          uint32(branchArms.x shr 32) == candidate.loopBranch.yes and
          branchArms.y == candidate.loopBranch.no and
          readTarget.y == cycle.prefix.header

      proc flatX86WideWorker(f: var FlatFrame, offset: uint32): uint32 =
        ## One linked image returns only complete receipts or an already-charged read replay.
        let saved = if int(offset) < f.x86Original.len: f.x86Original[int(offset)] else: nil
        if saved == nil: flatX86CycleAbort(); return flatStop
        let jit = f.x86Jit
        if jit == nil or not x86WideActive(jit): return saved(f, offset)
        if f.plan == nil or not x86WideBound(jit, cast[pointer](f.plan)):
          flatX86CycleAbort()
          return flatStop
        let candidate = x86WideCandidate(jit)
        let child = x86CycleSlot(jit, candidate.cycle.dirty.header)
        if child < 0 or not x86CycleBound(jit, child, cast[pointer](f.plan)) or
            f.preparationFailure != FlatError.None or not f.plan.allowNative or
            f.plan.singleStep or f.pricingKind != 0 or f.info.blockCharged or
            f.barrier != flatStop or offset != candidate.loopBranch.header or
            not flatX86WideMatches(f, candidate):
          retireX86Wide(jit)
          if f.handlers[int(offset)] == flatX86WideWorker:
            f.handlers[int(offset)] = saved
          return saved(f, offset)
        var memory = flatX86WideMemory(f, candidate)
        if memory.cycle.writePtr == nil: return saved(f, offset)
        var state = X86WideState(cycle: X86CycleState(gas: uint64(f.info.gas),
          attempts: f.remaining, visits: [0'u64, 0'u64, 0'u64], wordGroups: 0,
          lastCompleted: high(uint32), exitKind: 0, reserved: 0),
          outerVisits: [0'u64, 0'u64, 0'u64, 0'u64], childCalls: 0)
        let startGas = state.cycle.gas
        let startAttempts = state.cycle.attempts
        let receipt = callX86WideCycle(jit, f.info.registers, memory, f.dirtyPages, state)
        if receipt == 0: return saved(f, offset)
        if receipt shr 32 != 1: flatX86CycleAbort(); return flatStop
        let next = uint32(receipt and 0xffffffff'u64)
        if not flatX86WideReceiptValid(candidate, startGas, startAttempts, state, next) or
            not recordX86WideCycle(jit, candidate, state):
          flatX86CycleAbort()
          return flatStop
        f.info.gas = MachineGas(state.cycle.gas)
        f.remaining = state.cycle.attempts
        f.info.blockCharged = state.cycle.exitKind == 3
        if state.cycle.lastCompleted != high(uint32):
          let completed = state.cycle.lastCompleted
          let headers = [candidate.cycle.prefix, candidate.cycle.dirty,
            candidate.cycle.tail, candidate.cycle.outside, candidate.loopGuard,
            candidate.loopBranch, candidate.readBlock]
          for header in headers:
            if completed == header.header:
              f.stoppedAt = header.terminal
              f.reservation = header.header or flatReservationHeaderFlag
              break
          f.attemptedExit = false
          f.barrier = flatStop
        if state.cycle.exitKind == 3:
          f.reservation = candidate.readBlock.header or flatReservationHeaderFlag
          if int(next) >= f.handlers.len: flatX86CycleAbort(); return flatStop
          let selected = f.handlers[int(next)]
          return selected(f, next)
        if state.cycle.exitKind == 2: return next
        if next == offset: return saved(f, offset)
        next

    proc flatX86MemoryCycleImageProof*(f: FlatFrame, prefixPc: uint32,
        image: var seq[byte]): bool =
      ## A private witness can inspect exact generated bytes without publishing or executing x86.
      image = @[]
      var candidate = default(X86MemoryCycleCandidate)
      if not flatX86SealMemoryCycle(f, prefixPc, candidate): return false
      buildX86MemoryCycleImage(candidate, flatX86CycleEmission(f, candidate), image)

    proc flatX86InstallMemoryCycle(f: var FlatFrame, prefixPc: uint32): bool =
      ## Publish one sealed child; refusal leaves the original checked dirty header installed.
      var candidate = default(X86MemoryCycleCandidate)
      if not flatX86SealMemoryCycle(f, prefixPc, candidate): return false
      let jit = f.x86Jit
      if jit == nil or x86CycleSlot(jit, candidate.dirty.header) >= 0: return false
      if int(candidate.dirty.header) >= f.handlers.len or
          f.handlers[int(candidate.dirty.header)] != flatChargedWordLoop: return false
      let published = publishX86MemoryCycle(jit, candidate,
        flatX86CycleEmission(f, candidate), cast[pointer](f.plan))
      if published < 0: return false
      if f.x86Original.len < f.handlers.len: f.x86Original.setLen(f.handlers.len)
      f.x86Original[int(candidate.dirty.header)] = f.handlers[int(candidate.dirty.header)]
      f.handlers[int(candidate.dirty.header)] = flatX86CycleWorker
      true

    when defined(pvmX86MemoryCycleNativeProof):
      proc flatX86InstallMemoryCycleProof*(f: var FlatFrame, prefixPc: uint32): bool =
        ## Private witness uses the same source-bound child publisher as default admission.
        flatX86InstallMemoryCycle(f, prefixPc)

    when defined(pvmX86WideCycleProof):
      proc flatX86WideImageProof*(f: FlatFrame, prefixPc: uint32,
          image: var seq[byte]): bool =
        ## Prospective source-image renderer uses a synthetic aligned child address.
        image = @[]
        var candidate = default(X86WideCycleCandidate)
        var emission = default(X86WideEmission)
        if not flatX86SealWideCycle(f, prefixPc, candidate) or
            not flatX86WideEmission(f, candidate, emission): return false
        buildX86WideCycleImage(candidate, emission, 16'u32, 0'u32, image)

      proc flatX86WidePublishedImageProof*(f: FlatFrame,
          image: var seq[byte]): bool =
        ## Retained publication identity for the cold B/C timing control.
        image = @[]
        let jit = f.x86Jit
        if jit == nil or not x86WideBound(jit, cast[pointer](f.plan)):
          return false
        var emission = default(X86WideEmission)
        if not flatX86WideEmission(f, x86WideCandidate(jit), emission):
          return false
        x86WidePublishedSourceImage(jit, emission, image)

    func flatX86WideStatistics*(f: FlatFrame): array[2, uint64] =
      ## Validated wider entries and canonical replay refusals only.
      let jit = f.x86Jit
      if jit == nil: default(array[2, uint64])
      else: x86WideStatistics(jit)

    func flatX86MemoryCycleStatistics*(f: FlatFrame): array[2, uint64] =
      ## Validated narrow child calls and groups exclude dormant published code.
      let jit = f.x86Jit
      if jit == nil: default(array[2, uint64])
      else: x86MemoryCycleStatistics(jit)

    when defined(pvmX86WideParentRefusalWitness):
      func flatX86WidePendingCountWitness*(f: FlatFrame): uint32 =
        ## Test-only count proves unrelated startup backedges fill the bounded source table.
        uint32(f.x86WideAdmission.count)

      proc flatX86RefuseWideParentOnceWitness*(f: var FlatFrame) =
        ## Test-only refusal happens after dormant child publication and before parent publication.
        if f.x86Jit == nil: f.x86Jit = newX86Jit()
        let jit = f.x86Jit
        assert jit != nil
        if jit != nil: x86WideRefuseParentOnceWitness(jit)

    when defined(pvmX86WideCycleProof):
      func flatX86WideStatisticsProof*(f: FlatFrame): array[2, uint64] =
        ## Preserve the private witness name over the production counter.
        flatX86WideStatistics(f)

    proc flatX86InstallWideCycle(f: var FlatFrame, prefixPc: uint32,
        childPublished: var bool, activateParent = true,
        proofChildFirst = false): bool =
      ## Default admission publishes both images before either handler changes. Private proof
      ## controls may install the narrow child first to retain their exact dormant-parent lane.
      childPublished = false
      var candidate = default(X86WideCycleCandidate)
      var emission = default(X86WideEmission)
      if not flatX86SealWideCycle(f, prefixPc, candidate) or
          not flatX86WideEmission(f, candidate, emission): return false
      let jit = f.x86Jit
      if jit == nil or f.plan == nil or x86WideActive(jit) or
          not f.plan.allowNative or f.plan.singleStep or f.pricingKind != 0:
        return false
      let dirty = int(candidate.cycle.dirty.header)
      let branch = int(candidate.loopBranch.header)
      if dirty >= f.handlers.len or branch >= f.handlers.len or
          f.handlers[dirty] != flatChargedWordLoop or
          f.handlers[branch] != flatCharge or
          (dirty < f.x86Original.len and f.x86Original[dirty] != nil) or
          (branch < f.x86Original.len and f.x86Original[branch] != nil) or
          x86CycleSlot(jit, candidate.cycle.dirty.header) >= 0:
        return false
      if f.x86Original.len < f.handlers.len: f.x86Original.setLen(f.handlers.len)
      var child = -1
      if proofChildFirst:
        if not flatX86InstallMemoryCycle(f, prefixPc): return false
        child = x86CycleSlot(jit, candidate.cycle.dirty.header)
      else:
        child = publishX86MemoryCycle(jit, candidate.cycle,
          flatX86CycleEmission(f, candidate.cycle), cast[pointer](f.plan))
      if child < 0: return false
      childPublished = true
      if not x86CycleBound(jit, child, cast[pointer](f.plan)) or
          x86CycleCandidate(jit, child) != candidate.cycle or
          f.handlers[branch] != flatCharge:
        return false
      if proofChildFirst:
        if f.x86Original[dirty] != flatChargedWordLoop or
            f.handlers[dirty] != flatX86CycleWorker: return false
      elif f.handlers[dirty] != flatChargedWordLoop or
          f.x86Original[dirty] != nil: return false
      if not publishX86WideCycle(jit, candidate, emission, child,
          cast[pointer](f.plan)): return false
      if not proofChildFirst:
        f.x86Original[dirty] = f.handlers[dirty]
        f.handlers[dirty] = flatX86CycleWorker
      # Private timing can leave only the parent handler dormant after identical publication.
      if activateParent:
        f.x86Original[branch] = f.handlers[branch]
        f.handlers[branch] = flatX86WideWorker
      true

    when defined(pvmX86WideCycleProof):
      proc flatX86InstallWideCycleProof*(f: var FlatFrame,
          prefixPc: uint32, childInstalled: var bool,
          activateParent = true): bool =
        ## Private witness can keep its narrow child active with a dormant parent.
        flatX86InstallWideCycle(f, prefixPc, childInstalled, activateParent, true)

    proc flatX86ColdWideAdmission(f: var FlatFrame, tail: uint32) =
      ## Resolve a tail's copied backedge once; try pending source PCs only at an invocation boundary.
      ## Sixteen pending sources and thirty-two boundary attempts each bound work without an owner-wide
      ## negative shape latch. A refused source leaves every original checked worker available.
      let jit = f.x86Jit
      if f.plan == nil or jit == nil or not f.plan.allowNative or f.plan.singleStep or
          f.preparationFailure != FlatError.None or f.pricingKind != 0 or
          not x86WideCanPublish(jit): return
      if tail != flatStop:
        if int(tail) >= f.arguments.len or int(tail) >= f.handlers.len or
            f.handlers[int(tail)] != flatBranch[173]: return
        var prefix = default(X86MemoryCycleHeader)
        let target = uint32(f.arguments[int(tail)].x shr 32)
        if not flatX86CompleteTarget(f, target, prefix) or prefix.opcode != 1 or
            prefix.span < 4 or prefix.kind notin {X86MemoryCycleHandlerKind.Ordinary,
              X86MemoryCycleHandlerKind.NativeWhole,
              X86MemoryCycleHandlerKind.NativeProbe,
              X86MemoryCycleHandlerKind.NativeRegion}: return
        var opcodes = default(array[4, byte])
        var operations = 0
        for ordinal in prefix.ordinal..<prefix.ordinal+prefix.span:
          let opcode = f.plan.facts[int(ordinal)].opcode
          if opcode != 2:
            if operations >= opcodes.len: return
            opcodes[operations] = opcode
            inc operations
        if operations != 4 or opcodes != [51'u8, 200, 149, 1]: return
        if int(prefix.pc) >= f.plan.factAt.len: return
        if f.x86WideAdmission.seen.len == 0:
          f.x86WideAdmission.seen = newSeq[byte]((f.plan.factAt.len+7) div 8)
        let byteIndex = int(prefix.pc) div 8
        let mask = 1'u8 shl (int(prefix.pc) mod 8)
        if (f.x86WideAdmission.seen[byteIndex] and mask) != 0: return
        for index in 0..<int(f.x86WideAdmission.count):
          if f.x86WideAdmission.probes[index].pc == prefix.pc: return
        var index = int(f.x86WideAdmission.count)
        if index == f.x86WideAdmission.probes.len:
          # A late source may displace the most-attempted pending source; neither is a guest refusal.
          index = 0
          for candidate in 1..<f.x86WideAdmission.probes.len:
            if f.x86WideAdmission.probes[candidate].attempts >
                f.x86WideAdmission.probes[index].attempts: index = candidate
        else:
          inc f.x86WideAdmission.count
        f.x86WideAdmission.probes[index] = FlatX86WideProbe(pc: prefix.pc, attempts: 0)
        f.x86WideAdmission.seen[byteIndex] = f.x86WideAdmission.seen[byteIndex] or mask
        return
      if f.reason != oracle.StepError.None or f.barrier != flatStop: return
      var index = 0
      while index < int(f.x86WideAdmission.count):
        let pc = f.x86WideAdmission.probes[index].pc
        var childInstalled = false
        let before = x86Clock()
        let installed = flatX86InstallWideCycle(f, pc, childInstalled)
        jit.compilationNs += x86Clock()-before
        if installed:
          f.x86WideAdmission.count = 0
          return
        inc f.x86WideAdmission.probes[index].attempts
        if childInstalled or f.x86WideAdmission.probes[index].attempts >= 32:
          let last = int(f.x86WideAdmission.count)-1
          f.x86WideAdmission.probes[index] = f.x86WideAdmission.probes[last]
          dec f.x86WideAdmission.count
        else:
          inc index

    func flatX86MemoryCycleProofStatistics*(f: FlatFrame): array[2, uint64] =
      ## Only validated native calls and completed four-block groups appear in the private receipt.
      let jit = f.x86Jit
      if jit == nil: default(array[2, uint64])
      else: x86MemoryCycleStatistics(jit)

    func flatX86CycleTailVisitsProof*(f: FlatFrame): uint64 =
      ## Counts only validated native tail completions, not checked fallback reads.
      let jit = f.x86Jit
      if jit == nil: 0'u64
      else: x86MemoryCycleTailVisits(jit)

    func flatX86CycleBoundaryProof*(f: FlatFrame): array[7, uint64] =
      ## Private literals can inspect the exact unstarted/paid/refund bookkeeping after fallback.
      [f.remaining, uint64(f.reservation), uint64(f.stoppedAt),
        uint64(if f.attemptedExit: 1 else: 0),
        uint64(if f.info.blockCharged: 1 else: 0), uint64(f.dirtyIndices.len),
        (if f.dirtyPages.len == 0: 0'u64 else: f.dirtyPages[0])]

    proc flatX86CycleDescriptorProof*(f: var FlatFrame,
        candidate: X86MemoryCycleCandidate): array[7, uint64] =
      ## Report only the fresh descriptor ranges, never its borrowed invocation pointers.
      let memory = flatX86CycleMemory(f, candidate)
      [uint64(if memory.readPtr == nil: 0 else: 1), memory.readFirst,
        memory.readEnd, uint64(if memory.writePtr == nil: 0 else: 1),
        memory.writeFirst, memory.writeEnd, uint64(memory.dirtyWords)]

    func flatX86CycleRegionStatusProof*(f: FlatFrame): uint8 =
      ## Inspect the separate pure-region owner without exposing its code offset or invocation pointer.
      let jit = f.x86Jit
      if jit == nil: 0'u8 else: x86RegionStatus(jit)

    proc flatX86PublishIndependentRegionProof*(f: var FlatFrame): bool =
      ## Publish one inert pure-region image solely to prove the cycle retains the same region owner.
      let jit = f.x86Jit
      if jit == nil: return false
      if x86RegionStatus(jit) == 2: return true
      if x86RegionStatus(jit) != 0: return false
      var body = default(X86Block)
      emitX86Operation(body, 149'u8, default(RegisterSlots), 1)
      emitX86Branch(body, 171'u8, default(RegisterSlots), 0, 500, 501)
      var blocks = default(array[2, X86RegionBlock])
      blocks[0] = X86RegionBlock(header: 500, span: 2, operations: 2,
        yes: 500, no: 501, price: 3, body: move(body))
      publishX86Region(jit, blocks, 1)

    func flatX86CycleReceiptProof*(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32): bool =
      ## A positive and corrupted synthetic ledger exercise the same production validator.
      flatX86CycleReceiptValid(candidate, startGas, startAttempts, state, next)

    proc flatX86CycleRequireReceiptProof*(candidate: X86MemoryCycleCandidate, startGas,
        startAttempts: uint64, state: X86CycleState, next: uint32) =
      ## A child process must observe unconditional abort on a corrupted post-native receipt.
      if not flatX86CycleReceiptValid(candidate, startGas, startAttempts, state, next):
        flatX86CycleAbort()

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  proc flatArmUpgrade(f: var FlatFrame, offset: uint32): bool
    ## A positive original branch cache is required before any native continuation is published.

  proc flatArmRunNext[ClearPaid: static[bool]](f: var FlatFrame, offset: uint32): uint32 =
    ## A complete checked reservation precedes native arithmetic/branch work; no native path can exit mid-prefix.
    block:
      # The exclusive frame retains its cache throughout this non-host call; only disjoint register bytes are borrowed mutably.
      let jit {.cursor.} = f.armJit
      assert jit != nil
      if jit != nil:
        let destination = callArmBranch(jit, offset, f.info.registers)
        assert int(destination) < f.handlers.len
        when ClearPaid: f.info.blockCharged = false
        return destination
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmBranch(f: var FlatFrame, offset: uint32): uint32 =
    ## Partial source prefixes always reenter the original checked operations and exact temporary barrier.
    if f.barrier != flatStop:
      let original = f.armOriginal[int(offset)]
      assert original != nil
      if original != nil: return original(f, offset)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    flatArmRunNext[true](f, offset)

  proc flatArmCheckedTail(f: var FlatFrame, offset: uint32): uint32 =
    ## A checked prefix keeps its original fault and memory effects, then enters an already validated native suffix.
    flatReserve(f, offset)
    let next = offset+1
    let selected = f.handlers[int(next)]
    let destination = selected(f, next)
    if f.barrier == flatStop and destination == offset+3 and
        int(destination) < f.handlers.len and
        f.handlers[int(destination)] == flatArmBranch:
      return flatArmBranch(f, destination)
    destination

  func flatArmDirtyShape(f: FlatFrame, header: uint32): bool =
    ## One sealed five-op source block; neither admission nor code emission depends on a guest PC.
    if int(header)+6 >= f.handlers.len or f.pricingKind != 0: return false
    let start = f.sites[int(header)]
    if f.sites[int(header+1)] != start or f.arguments[int(header)].y != 5: return false
    for step in 2..5:
      if f.sites[int(header)+step] != start+uint32(step-1): return false
    if f.sites[int(header+6)] != start+5: return false
    if f.handlers[int(header+3)] != flatArmBranch: return false
    let prefix = f.plan.facts[int(f.sites[int(header+1)])]
    let store = f.plan.facts[int(f.sites[int(header+2)])]
    if prefix.opcode != 198 or store.opcode != 120 or
        prefix.args.slots.destinationIndex == store.args.slots.bIndex: return false
    if f.plan.facts[int(f.sites[int(header+3)])].opcode != 149 or
        f.plan.facts[int(f.sites[int(header+4)])].opcode != 149 or
        f.plan.facts[int(f.sites[int(header+5)])].opcode != 171: return false
    let branch = f.arguments[int(header+5)]
    let yes = uint32(branch.x shr 32)
    let no = branch.y
    (yes == header and no != header) or (no == header and yes != header)

  func flatArmWordShape(f: FlatFrame, header: uint32): ArmDirtyWordShape =
    ## Only sealed, disjoint source roles authorize a word candidate; every value remains invocation-local.
    let prefix = f.arguments[int(header+1)]
    let store = f.arguments[int(header+2)]
    let baseStep = f.arguments[int(header+3)]
    let shiftStep = f.arguments[int(header+4)]
    let branch = f.arguments[int(header+5)]
    let source = prefix.slots.aIndex
    let shift = prefix.slots.bIndex
    let destination = prefix.slots.destinationIndex
    let base = store.slots.bIndex
    let bound = branch.slots.bIndex
    let roles = [source, shift, destination, base, bound]
    for i in 0..<5:
      for j in i+1..<5:
        if roles[i] == roles[j]: return default(ArmDirtyWordShape)
    if uint32(branch.x shr 32) != header or store.slots.aIndex != destination or
        baseStep.slots.aIndex != base or baseStep.slots.bIndex != base or baseStep.x != 1 or
        shiftStep.slots.aIndex != shift or shiftStep.slots.bIndex != shift or shiftStep.x != 8 or
        branch.slots.aIndex != base:
      return default(ArmDirtyWordShape)
    ArmDirtyWordShape(enabled: true, source: source, shift: shift, destination: destination,
      base: base, bound: bound)

  proc flatArmDirtyLoop(f: var FlatFrame, offset: uint32): uint32 =
    ## Every failed native guard returns the unstarted charged header with prior whole blocks published.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    let charge = f.arguments[int(offset)]
    if f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop or
        not armDirtyLoopChargeMatches(jit, offset, charge.y, charge.x):
      return flatArmCheckedTail(f, offset)
    var state = [uint64(f.info.gas), f.remaining, 0'u64, 0'u64, 0'u64, 0'u64, 0'u64, 0'u64]
    let destination = callArmDirtyLoopContext(jit, f.info.registers, f.armMemory, f.dirtyPages, state)
    f.info.gas = MachineGas(state[0])
    f.remaining = state[1]
    f.info.blockCharged = false
    assert int(destination) < f.handlers.len
    if int(destination) >= f.handlers.len:
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    if destination == offset: return flatArmCheckedTail(f, offset)
    destination

  proc flatArmDirtyBody(f: FlatFrame, offset: uint32): ArmRegionBlock {.noinline.} =
    ## Rebuild the same sealed five-op dirty source IR for standalone and resident lowering.
    let branch = f.arguments[int(offset+5)]
    var native = newArmRegionBody()
    let prefix = f.plan.facts[int(f.sites[int(offset+1)])]
    let store = f.plan.facts[int(f.sites[int(offset+2)])]
    emitArmOperation(native, prefix.opcode, prefix.args.slots, prefix.args.x)
    emitArmDirtyRegionByteStore(native, store.args.slots.aIndex)
    for step in 3..4:
      let fact = f.plan.facts[int(f.sites[int(offset)+step])]
      emitArmOperation(native, fact.opcode, fact.args.slots, fact.args.x)
    emitArmBranch(native, 171, branch.slots, flatSext32(uint32(branch.x and 0xffffffff'u64)),
        uint32(branch.x shr 32), branch.y)
    let charge = f.arguments[int(offset)]
    result = ArmRegionBlock(header: offset, span: charge.y, operations: 5,
        yes: uint32(branch.x shr 32), no: branch.y, price: charge.x, body: move(native))

  proc flatArmDirtyProbeTail(f: var FlatFrame, offset: uint32): uint32 =
    ## Only a genuinely completed self-loop contributes to the bounded admission threshold.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    if armDirtyLoopStatus(jit) != 0:
      f.handlers[int(offset)] = flatArmCheckedTail
      return flatArmCheckedTail(f, offset)
    let destination = flatArmCheckedTail(f, offset)
    if f.barrier != flatStop or f.info.blockCharged: return destination
    let branch = f.arguments[int(offset+5)]
    if destination != offset and destination != uint32(branch.x shr 32) and
        destination != branch.y: return destination
    let probe = armDirtyLoopObserve(jit, offset, destination == offset)
    if probe == 0: return destination
    if probe == 2:
      f.handlers[int(offset)] = flatArmCheckedTail
      return destination
    if not flatArmDirtyShape(f, offset):
      f.handlers[int(offset)] = flatArmCheckedTail
      return destination
    let before = armClock()
    let store = f.plan.facts[int(f.sites[int(offset+2)])]
    let item = flatArmDirtyBody(f, offset)
    let word = flatArmWordShape(f, offset)
    let admitted = publishArmDirtyLoop(jit, item, store.args.slots.bIndex,
        uint32(store.args.x and 0xffffffff'u64), word)
    jit.compilationNs+=armClock()-before
    f.handlers[int(offset)] = if admitted: flatArmDirtyLoop else: flatArmCheckedTail
    destination

  proc flatArmEnter(f: var FlatFrame, offset: uint32): uint32 =
    ## Preserve the canonical quota/gas/error ordering before a direct full-block native handoff.
    flatReserve(f, offset)
    if f.barrier != flatStop:
      let selected = f.handlers[int(offset+1)]
      return selected(f, offset+1)
    block:
      # End the cache borrow before the next helper receives the whole mutable frame; no owner reference needs retaining.
      let jit {.cursor.} = f.armJit
      assert jit != nil
      if jit != nil: inc jit.headerCalls
    flatArmRunNext[true](f, offset+1)

  proc flatArmWhole(f: var FlatFrame, offset: uint32): uint32 =
    ## Complete pure blocks cannot observe a transient paid flag; every partial/paid/error case uses the original entry.
    let args = f.arguments[int(offset)]
    if f.barrier != flatStop or f.info.blockCharged or f.remaining < uint64(args.y) or
        uint64(f.info.gas) < args.x:
      # These nonmutating guards preserve zero-budget, gas and resumed-block precedence in the existing reservation worker.
      return flatArmEnter(f, offset)
    # The sealed suffix includes its cached conditional: no host, fault or exit can observe these two omitted paid writes.
    f.info.gas = MachineGas(uint64(f.info.gas)-args.x)
    f.remaining-=uint64(args.y)
    # Retain the source-bound header; a later attempted exit alone resolves its exact reserved endpoint.
    f.reservation = offset or flatReservationHeaderFlag
    block:
      # The cache borrow ends before the whole invocation frame is passed to native execution.
      let jit {.cursor.} = f.armJit
      assert jit != nil
      if jit != nil: inc jit.headerCalls
    flatArmRunNext[false](f, offset+1)

  proc flatArmProbeWhole(f: var FlatFrame, offset: uint32): uint32 =
    ## At most eight complete visits per header discover actual two-block cycles; ordinary dispatch then has no probe.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    if f.pricingKind != 0 or armRegionStatus(jit) != 0:
      # A saved region fallback may still refer to this worker; never overwrite the region's active root handler.
      if f.handlers[int(offset)] == flatArmProbeWhole: f.handlers[int(offset)] = flatArmWhole
      return flatArmWhole(f, offset)
    let args = f.arguments[int(offset)]
    let complete = f.barrier == flatStop and not f.info.blockCharged and
        f.remaining >= uint64(args.y) and uint64(f.info.gas) >= args.x
    let destination = flatArmWhole(f, offset)
    if not complete: return destination
    # Only genuinely completed adjacent headers establish a closed round; partial reservations do not consume probes.
    let previous = f.armPreviousHeader
    let closed = f.armPreviousValid and f.armPreviousNext == offset and
        destination == previous and previous != offset
    f.armPreviousHeader = offset
    f.armPreviousNext = destination
    f.armPreviousValid = true
    if closed:
      var connected = destination
      if flatArmCycle(f, previous, offset, flatStop, connected): return connected
    if armRegionStatus(jit) != 0:
      # Failed publication can mark the sole region refused; retain its original checked continuation without retrying.
      if f.handlers[int(offset)] == flatArmProbeWhole: f.handlers[int(offset)] = flatArmWhole
    elif armFinishProbe(jit, offset):
      # Exhaustion permanently restores the existing hot worker, with no status or history test on subsequent visits.
      if f.handlers[int(offset)] == flatArmProbeWhole: f.handlers[int(offset)] = flatArmWhole
    destination

  proc flatArmExecute(f: var FlatFrame, offset: uint32): uint32 =
    ## Partial budgets retain original atomic handler behaviour, including a second-node barrier.
    if f.barrier != flatStop:
      let original = f.armOriginal[int(offset)]
      assert original != nil
      if original != nil: return original(f, offset)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    block:
      # Native arithmetic cannot replace the frame-owned cache or invoke a host; the owner outlives this register borrow.
      let jit {.cursor.} = f.armJit
      assert jit != nil
      if jit != nil: return callArmEntry(jit, offset, f.info.registers)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmPending(f: var FlatFrame, offset: uint32): uint32 =
    ## First execution retains original branch resolution; only subsequent positive cached capability enables promotion.
    if f.barrier != flatStop: return flatArmExecute(f, offset)
    if flatArmUpgrade(f, offset): return flatArmBranch(f, offset)
    flatArmExecute(f, offset)

  func flatArmCachedBranch(f: FlatFrame, offset: uint32): bool =
    ## Exact original handler identity certifies both arms already passed genuine source and preparation checks.
    let code = f.plan.facts[int(f.sites[int(offset)])].opcode
    case code
    of 81: f.handlers[int(offset)] == flatBranch[81]
    of 82: f.handlers[int(offset)] == flatBranch[82]
    of 83: f.handlers[int(offset)] == flatBranch[83]
    of 84: f.handlers[int(offset)] == flatBranch[84]
    of 85: f.handlers[int(offset)] == flatBranch[85]
    of 86: f.handlers[int(offset)] == flatBranch[86]
    of 87: f.handlers[int(offset)] == flatBranch[87]
    of 88: f.handlers[int(offset)] == flatBranch[88]
    of 89: f.handlers[int(offset)] == flatBranch[89]
    of 90: f.handlers[int(offset)] == flatBranch[90]
    of 170: f.handlers[int(offset)] == flatBranch[170]
    of 171: f.handlers[int(offset)] == flatBranch[171]
    of 172: f.handlers[int(offset)] == flatBranch[172]
    of 173: f.handlers[int(offset)] == flatBranch[173]
    of 174: f.handlers[int(offset)] == flatBranch[174]
    of 175: f.handlers[int(offset)] == flatBranch[175]
    else: false

  proc flatArmMixed(f: var FlatFrame, header: uint32): uint32 =
    ## The original checked header charges once; a guard exit resumes at its exact paid memory op.
    assert f.armJit != nil and int(header) < f.armOriginal.len
    let original = f.armOriginal[int(header)]
    assert original != nil
    let charge = f.arguments[int(header)]
    var terminal = flatStop
    var operationCount = 0'u32
    block:
      let jit {.cursor.} = f.armJit
      assert jit != nil
      terminal = armEnding(jit, header)
      operationCount = armMixedOperationCount(jit, header)
    if f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop or
        f.remaining < uint64(charge.y) or uint64(f.info.gas) < charge.x:
      return original(f, header)
    # Publication certified the source-bound terminal arms. Temporary budget patching
    # is excluded above; stream reuse preserves these cached offsets and their exact plan.
    # This complete, unpaid fast entry cannot expose its paid state until native guard replay.
    f.info.gas = MachineGas(uint64(f.info.gas)-charge.x)
    f.remaining-=uint64(charge.y)
    f.reservation = header or flatReservationHeaderFlag
    var state = default(ArmMixedState)
    var next = flatStop
    block:
      let jit {.cursor.} = f.armJit
      assert jit != nil
      next = callArmMixedContext(jit, header, f.info.registers, f.armMemory, f.dirtyPages, state)
    if state[0] == 1:
      let branch = f.arguments[int(terminal)]
      if (next == uint32(branch.x shr 32) or next == branch.y) and
          state[4] == uint64(operationCount):
        return next
    # Guard replay and every malformed receipt retain the original paid reservation.
    f.info.blockCharged = true
    if state[0] == 2 and next > header and next < terminal and int(next) < f.sites.len:
      let fact = f.plan.facts[int(f.sites[int(next)])]
      if fact.opcode notin 120'u8..130'u8 or fact.ending or not fact.fallthrough:
        return flatLocal(f, header, oracle.StepError.InvalidPreparedProgram)
      # Publication certifies one lowered operation per physical body node.
      let completed = uint64(next-header-1)
      if state[4] != completed:
        return flatLocal(f, header, oracle.StepError.InvalidPreparedProgram)
      # The current stream worker may be fused or native; this immutable fact is the one-op checked worker.
      return fact.handler(f, next)
    flatLocal(f, header, oracle.StepError.InvalidPreparedProgram)

  const armMixedMaximumSourceSpan = 32

  proc flatArmPublishMixed(f: var FlatFrame, header, terminal: uint32): bool =
    let jit = f.armJit
    assert jit != nil and flatArmCachedBranch(f, terminal)
    # Plan from ordered source events, including repeated writes that an OR/XOR mask cannot prove absent.
    var operations: seq[FlatMixedOp] = @[]
    var used = 0'u32
    for current in header+1..<terminal:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      let slots = fact.args.slots
      used = used or (1'u32 shl int(slots.aIndex)) or
          (1'u32 shl int(slots.bIndex)) or (1'u32 shl int(slots.destinationIndex))
      var entry = default(FlatMixedOp)
      if fact.opcode in 120'u8..130'u8:
        assert fact.opcode >= 120 and fact.opcode <= 130 # Keep the admitted conversion proof local.
        let access = indirectMemoryAccess(range[120..130](fact.opcode))
        entry.memory = true
        entry.store = access.kind == IndirectMemoryKind.Store
        entry.base = uint32(slots.bIndex)
        entry.writes = not entry.store
        entry.destination = uint32(slots.aIndex)
        entry.displacement = uint32(fact.args.x and 0xffffffff'u64)
        entry.width = access.width
      elif supportedArmOpcode(fact.opcode):
        entry.writes = true
        entry.destination = uint32(slots.destinationIndex)
      else: return false
      operations.add(entry)
    let branch = f.plan.facts[int(f.sites[int(terminal)])]
    let branchSlots = branch.args.slots
    used = used or (1'u32 shl int(branchSlots.aIndex)) or
        (1'u32 shl int(branchSlots.bIndex)) or
        (1'u32 shl int(branchSlots.destinationIndex))
    var groups = default(array[2, FlatMixedGroup])
    var groupOf = default(array[armMixedMaximumSourceSpan, int])
    for index in 0..<armMixedMaximumSourceSpan: groupOf[index] = -1
    var groupCount = 0
    for base in 0..<13:
      if groupCount == 2: break
      var first = -1
      var last = -1
      var count = 0
      var minDisp = high(uint32)
      var maxEnd = 0'u32
      var writable = false
      var valid = true
      for index in 0..<operations.len:
        let entry = operations[index]
        if not entry.memory or entry.base != uint32(base): continue
        if first < 0: first = index
        last = index
        inc count
        if entry.displacement < minDisp: minDisp = entry.displacement
        let end64 = uint64(entry.displacement)+uint64(entry.width)
        if end64 > uint64(high(uint32)): valid = false
        elif uint32(end64) > maxEnd: maxEnd = uint32(end64)
        if entry.store: writable = true
      if count < 2 or not valid or maxEnd-minDisp > 4096: continue
      # A write at the first access still changes the base before the next member.
      for index in first..<last:
        if operations[index].writes and operations[index].destination == uint32(base):
          valid = false
          break
      if not valid: continue
      var lane = 0'u32
      for candidate in 4'u32..16'u32:
        let bit = 1'u32 shl int(candidate-4)
        if (used and bit) == 0:
          lane = candidate
          used = used or bit
          break
      if lane == 0: continue
      groups[groupCount] = FlatMixedGroup(writable: writable,
          first: uint32(first), minDisp: minDisp,
          maxEnd: maxEnd, lane: lane)
      for index in first..last:
        if operations[index].memory and operations[index].base == uint32(base):
          groupOf[index] = groupCount
      inc groupCount
    if groupCount == 0: return false # Retain the accepted checked header when no window exists.
    var mixed = newArmMixedBody()
    for current in header+1..<terminal:
      # Refuse publication unless every preceding physical node lowered exactly once.
      if armMixedLowered(mixed) != current-header-1: return false
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.opcode in 120'u8..130'u8:
        assert fact.opcode >= 120 and fact.opcode <= 130
        let index = int(current-header-1)
        let groupIndex = groupOf[index]
        if groupIndex >= 0:
          let group = groups[groupIndex]
          emitArmMixedWindowMemory(mixed, range[120..130](fact.opcode), fact.args.slots,
              uint32(fact.args.x and 0xffffffff'u64), current, group.minDisp,
              group.maxEnd, group.lane, uint32(index) == group.first, group.writable)
        else:
          emitArmMixedMemory(mixed, range[120..130](fact.opcode), fact.args.slots,
              uint32(fact.args.x and 0xffffffff'u64), current)
      elif supportedArmOpcode(fact.opcode):
        emitArmMixedPure(mixed, fact.opcode, fact.args.slots, fact.args.x)
      else: return false
    let args = f.arguments[int(terminal)]
    emitArmMixedBranch(mixed, branch.opcode, args.slots,
        flatSext32(uint32(args.x and 0xffffffff'u64)), uint32(args.x shr 32), args.y)
    # The terminal branch contributes exactly one additional lowered operation.
    if armMixedLowered(mixed) != terminal-header: return false
    var words = armMixedInstructions(mixed)
    if words.len >= 1024:
      when defined(pvmArmMixedGroupReceipt):
        echo "ARM_MIXED_GROUP_OVERSIZE,", f.plan.facts[int(f.sites[int(header)])].pc, ",",
            branch.pc, ",", groupCount, ",", words.len
      return false
    let published = publishArmEntry(jit, header, terminal, armMixedLowered(mixed), words)
    if published:
      armMixedPublishedGroups(jit, uint32(groupCount))
      when defined(pvmArmMixedGroupReceipt):
        echo "ARM_MIXED_GROUP_PUBLISH,", f.plan.facts[int(f.sites[int(header)])].pc, ",",
            branch.pc, ",", groupCount
    published

  proc flatArmMixedProbe(f: var FlatFrame, header: uint32): uint32 =
    ## Count only source-owned header visits after both conditional arms have checked certificates.
    let jit = f.armJit
    assert jit != nil and int(header) < f.armOriginal.len
    let original = f.armOriginal[int(header)]
    assert original != nil
    let terminal = armEnding(jit, header)
    if f.pricingKind != 0:
      # A retained unpriced stream can be leased after selecting prices; retire its ineligible observer.
      f.handlers[int(header)] = original
      return original(f, header)
    if f.barrier == flatStop and not f.info.blockCharged and
        f.remaining >= uint64(f.arguments[int(header)].y) and
        uint64(f.info.gas) >= f.arguments[int(header)].x and
        flatArmCachedBranch(f, terminal) and armFinishProbe(jit, header):
      let before = armClock()
      let published = flatArmPublishMixed(f, header, terminal)
      jit.compilationNs+=armClock()-before
      if published:
        f.handlers[int(header)] = flatArmMixed
        return flatArmMixed(f, header)
      f.handlers[int(header)] = original
    original(f, header)

  proc flatArmTryMixedProbe(f: var FlatFrame, terminal: uint32) =
    ## Discover one general mixed source block when its terminal first enters the sealed stream.
    if f.pricingKind != 0: return # Priced headers cannot promote; retain their ordinary checked dispatch.
    if int(terminal) >= f.sites.len: return
    let ending = f.plan.facts[int(f.sites[int(terminal)])]
    if not ending.ending or ending.opcode notin {81'u8..90'u8, 170'u8..175'u8}:
      return
    var header = flatStop
    var candidate = terminal
    while candidate > 0 and terminal-candidate < uint32(armMixedMaximumSourceSpan):
      dec candidate
      if f.handlers[int(candidate)] != flatCharge: continue
      let charge = f.arguments[int(candidate)]
      if charge.y == 0 or charge.y > uint32(armMixedMaximumSourceSpan): continue
      let source = f.sites[int(candidate)]
      let sourceEnd = uint64(source)+uint64(charge.y)
      if sourceEnd != uint64(f.sites[int(terminal)])+1 or
          sourceEnd > uint64(f.plan.facts.len) or sourceEnd > uint64(high(uint32)) or
          f.plan.facts[int(source)].sourceCount != charge.y: continue
      # A folded noop has no body node. Every remaining node must cover this exact
      # ordinary header's ordered source facts, ending at the observed branch.
      var node = candidate+1
      var valid = true
      for ordinal in source..<uint32(sourceEnd):
        if f.plan.facts[int(ordinal)].opcode == 2: continue
        if node > terminal or f.sites[int(node)] != ordinal:
          valid = false
          break
        inc node
      if valid and node == terminal+1:
        header = candidate
        break
    if header == flatStop or terminal <= header+2: return
    var loads = 0
    var stores = 0
    for current in header+1..<terminal:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.ending or not fact.fallthrough: return
      if fact.opcode in 120'u8..123'u8: inc stores
      elif fact.opcode in 124'u8..130'u8: inc loads
      elif not supportedArmOpcode(fact.opcode): return
    if loads < 1 or stores < 1 or loads+stores < 2 or loads+stores > 16: return
    let jit = f.armJit
    if jit == nil or not armStartMixedProbe(jit, header, uint32(f.handlers.len),
        terminal): return
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(header)] = flatCharge
    f.handlers[int(header)] = flatArmMixedProbe

  proc flatArmUpgrade(f: var FlatFrame, offset: uint32): bool =
    ## Rebuild immutable arithmetic facts only after both existing scalar branch arms are admitted; no pricing/resolve is moved.
    let jit = f.armJit
    if jit == nil: return false
    let ending = armEnding(jit, offset)
    if not flatArmCachedBranch(f, ending): return false
    let before = armClock()
    var native = default(ArmBlock)
    var current = offset
    while current < ending:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      emitArmOperation(native, fact.opcode, fact.args.slots, fact.args.x)
      inc current
    let args = f.arguments[int(ending)]
    let fact = f.plan.facts[int(f.sites[int(ending)])]
    emitArmBranch(native, fact.opcode, args.slots, flatSext32(uint32(args.x and 0xffffffff'u64)),
        uint32(args.x shr 32), args.y)
    var words = armInstructions(native)
    let promoted = publishArmEntry(jit, offset, ending, ending-offset+1, words)
    jit.compilationNs+=armClock()-before
    if not promoted:
      # A full arena retains the already published arithmetic leaf; never replace a valid entry with a refusal marker.
      f.handlers[int(offset)] = flatArmExecute
      return false
    f.handlers[int(offset)] = flatArmBranch
    if offset > 0:
      let header = offset-1
      let plain: FlatHandler = flatCharge
      # Only an exact ordinary header owning this complete source suffix can fuse. Memo/errors/special shapes remain original.
      if f.handlers[int(header)] == plain and
          f.sites[int(ending)]+1 == f.sites[int(header)]+f.arguments[int(header)].y:
        f.armOriginal[int(header)] = plain
        assert f.arguments[int(header)].y > 0
        if f.pricingKind == 0 and armRegionStatus(jit) == 0:
          # Header coordinates already exist in the bounded source map; no extra table or per-iteration policy is needed.
          armStartProbe(jit, header)
          f.handlers[int(header)] = flatArmProbeWhole
        else:
          # A priced or already-connected owner keeps the established worker immediately.
          f.handlers[int(header)] = flatArmWhole
    # One checked pair may cover two source nodes before this positively promoted native suffix.
    # A complete ordinary header is the only entry that can make the direct tail call.
    if offset > 2:
      let header = offset-3
      let plain: FlatHandler = flatCharge
      if f.handlers[int(header)] == plain and f.sites[int(header)] == f.sites[int(header+1)] and
          f.sites[int(ending)]+1 == f.sites[int(header)]+f.arguments[int(header)].y and
          f.handlers[int(header+1)] != f.plan.facts[int(f.sites[int(header+1)])].handler:
        f.handlers[int(header)] = flatArmCheckedTail
        if flatArmDirtyShape(f, header): f.handlers[int(header)] = flatArmDirtyProbeTail
    true

  proc flatArmRegion(f: var FlatFrame, offset: uint32): uint32 =
    ## A fresh invocation context never escapes this call; guarded returns resume the original checked header.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    let active = armRegionCount(jit)
    var headers = [flatStop, flatStop, flatStop]
    var matched = true
    for index in 0..<active:
      # Read all original header coordinates before fallback; every source price/span still matches the complete cached record.
      headers[index] = armRegionHeader(jit, range[0..2](index))
      assert int(headers[index]) < f.arguments.len
      let charge = f.arguments[int(headers[index])]
      if not armRegionChargeMatches(jit, range[0..2](index), headers[index], charge.y, charge.x):
        matched = false
    for index in int(active)..<3:
      # Inactive records retain the original full sentinel/zero checks, including the unused third lane of a two-block region.
      if not armRegionChargeMatches(jit, range[0..2](index), flatStop, 0, 0): matched = false
    if f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop or
        offset != headers[0] or not matched:
      # Already-paid, partial or differently priced execution retains its original complete ordering.
      let original = f.armOriginal[int(offset)]
      assert original != nil
      if original != nil: return original(f, offset)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    var state = [uint64(f.info.gas), f.remaining, 0'u64, 0'u64, 0'u64]
    let destination = callArmRegion(jit, f.info.registers, state)
    f.info.gas = MachineGas(state[0])
    f.remaining = state[1]
    f.info.blockCharged = false
    assert int(destination) < f.handlers.len
    if int(destination) >= f.handlers.len: return flatLocal(f, offset,
        oracle.StepError.InvalidPreparedProgram)
    for index in 0..<active:
      let header = headers[index]
      if destination == header:
        # This block has not begun: original reservation preserves gas-before-partial-prefix and exact source PC/paid flags.
        let original = f.armOriginal[int(header)]
        assert original != nil
        if original != nil: return original(f, header)
        return flatLocal(f, header, oracle.StepError.InvalidPreparedProgram)
    destination

  proc flatArmCycle(f: var FlatFrame, first, middle, last: uint32, destination: var uint32): bool =
    ## One source-owned region follows an actual closed two/three-block round; all refusal paths keep checked dispatch.
    if f.pricingKind != 0 or f.barrier != flatStop or f.info.blockCharged: return false
    let jit = f.armJit
    if jit == nil: return false
    let status = armRegionStatus(jit)
    if status == 1: return false
    if status == 2:
      # A different rotation or independent loop returns to the ordinary dispatch rather than borrowing another root's code.
      if armRegionHeader(jit, 0) != first: return false
      destination = flatArmRegion(f, first)
      return true
    if f.handlers.len > 262144: return false
    discard armEntry(jit, first, uint32(f.handlers.len))
    let active: range[2..3] = if last == flatStop: 2 else: 3
    let headers = [first, middle, last]
    # Include successful regional body emission in the diagnostic bracket; full cold-call clocks already include it.
    let before = armClock()
    var blocks = default(array[3, ArmRegionBlock])
    for index in 0..<active:
      let header = headers[index]
      let charge = f.arguments[int(header)]
      var native = newArmRegionBody()
      var current = header+1
      var terminal = false
      while int(current) < f.handlers.len and current-header <= 64:
        # Header duplicates and an unsupported instruction stop this compiler before any publication or execution.
        if int(current)+1 < f.sites.len and f.sites[int(current)] == f.sites[int(
            current)+1]: return false
        let fact = f.plan.facts[int(f.sites[int(current)])]
        if fact.ending:
          if not flatArmCachedBranch(f, current): return false
          if f.sites[int(current)]+1 != f.sites[int(header)]+charge.y: return false
          let args = f.arguments[int(current)]
          emitArmBranch(native, fact.opcode, args.slots, flatSext32(uint32(args.x and
              0xffffffff'u64)), uint32(args.x shr 32), args.y)
          blocks[index] = ArmRegionBlock(header: header, span: charge.y, operations: current-header,
              yes: uint32(args.x shr 32), no: args.y, price: charge.x, body: move(native))
          terminal = true
          break
        if not fact.fallthrough or not supportedArmOpcode(fact.opcode): return false
        if active == 3 and fact.opcode == 151 and current-header < 64 and
            int(current)+1 < f.handlers.len:
          # Only genuine adjacent source nodes within this charged block can hide an overwritten intermediate shift.
          let next = current+1
          let nextHeader = int(next)+1 < f.sites.len and f.sites[int(next)] == f.sites[int(next)+1]
          if not nextHeader and f.sites[int(next)] == f.sites[int(current)]+1:
            let following = f.plan.facts[int(f.sites[int(next)])]
            if following.opcode == 152 and not following.ending and following.fallthrough and
                emitArmShiftPair(native, fact.args.slots, following.args.slots, fact.args.x,
                    following.args.x):
              current+=2 # Source spans/operation counts still include both original instructions.
              continue
        emitArmOperation(native, fact.opcode, fact.args.slots, fact.args.x)
        inc current
      if not terminal: return false
    let admitted = publishArmRegion(jit, blocks, active)
    jit.compilationNs+=armClock()-before
    if not admitted: return false
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    for index in 0..<active:
      let header = headers[index]
      # All active originals are retained for a guard exit at any block, but only the observed root changes dispatch.
      f.armOriginal[int(header)] = f.handlers[int(header)]
    f.handlers[int(first)] = flatArmRegion
    destination = flatArmRegion(f, first)
    true

  proc flatArmRegionStatistics*(f: FlatFrame): array[2, uint64] =
    ## A focused witness proves actual connected execution separately from ordinary arithmetic leaves.
    let jit = f.armJit
    if jit == nil: default(array[2, uint64])
    else: armRegionStatistics(jit)

  proc flatArmDirtyLoopStatistics*(f: FlatFrame): array[3, uint64] =
    let jit = f.armJit
    if jit == nil: default(array[3, uint64])
    else: armDirtyLoopStatistics(jit)

  proc flatArmMixedStatistics*(f: FlatFrame): array[4, uint64] =
    let jit = f.armJit
    if jit == nil: default(array[4, uint64])
    else: armMixedStatistics(jit)

  when defined(pvmArmMixedGroupReceipt) or defined(pvmArmDirtyLoopOwnerReceipt):
    proc flatArmMixedProbes*(f: FlatFrame): uint64 =
      ## Diagnostic active admission work distinguishes an ineligible probe from ordinary checked execution.
      result = 0
      for handler in f.handlers:
        # Count installed observers, including those that have not yet reached their promotion threshold.
        if handler == flatArmMixedProbe: inc result

  proc flatArmMixedGroupStatistics*(f: FlatFrame): array[3, uint64] =
    ## Private publication/guard activity, with no retained invocation memory.
    let jit = f.armJit
    if jit == nil: default(array[3, uint64])
    else: armMixedGroupStatistics(jit)

  proc flatArmDirtyWordGroups*(f: FlatFrame): uint64 =
    let jit = f.armJit
    if jit == nil: 0'u64
    else: armDirtyWordGroups(jit)

  proc flatArmMemory(f: var FlatFrame, offset: uint32): uint32 =
    ## A partial reservation uses the original source nodes; native guard refusal replays the untouched checked memory operation.
    if f.barrier == flatStop:
      block:
        # End all descriptor/register borrows before a guard failure invokes the full mutable checked worker.
        let jit {.cursor.} = f.armJit
        assert jit != nil
        if jit != nil:
          let destination = callArmMemoryContext(jit, offset, f.info.registers, f.armMemory)
          if destination != flatStop: return destination
    let original = f.armOriginal[int(offset)]
    assert original != nil
    if original != nil: return original(f, offset)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmReadBody(f: FlatFrame, offset, ending: uint32): ArmReadSpan {.noinline.}
  proc flatArmReadSpanBody(f: FlatFrame, offset, ending: uint32,
      native: var ArmReadSpan): bool {.noinline.}
    ## Cold shared read IR is defined with the standalone read publisher below.

  proc flatArmMemoryCycleShape(f: FlatFrame, readEntry, prefix: uint32,
      item: var ArmMemoryCycleBlock, prefixHandler: FlatHandler = flatCharge): bool =
    ## Capture a complete default-priced source graph with sealed targets and live native children.
    if f.pricingKind != 0 or f.barrier != flatStop or f.info.blockCharged:
      return false
    let jit = f.armJit
    if jit == nil or armDirtyLoopStatus(jit) != 2 or readEntry == 0: return false
    let tail = readEntry-1
    if int(prefix) >= f.handlers.len or f.handlers[int(prefix)] != prefixHandler or
        f.handlers[int(tail)] != flatCharge: return false
    let prefixCharge = f.arguments[int(prefix)]
    let first = f.sites[int(prefix)]
    let endingSource = uint64(first)+uint64(prefixCharge.y)
    if prefixCharge.y < 2 or prefixCharge.y > 64 or endingSource > uint64(f.plan.facts.len):
      return false
    var node = prefix+1
    var pure = 0'u32
    var dirty = flatStop
    for ordinal in uint64(first)..<endingSource:
      let fact = f.plan.facts[int(ordinal)]
      if fact.opcode == 2: continue
      if int(node) >= f.handlers.len or f.sites[int(node)] != uint32(ordinal): return false
      if ordinal+1 == endingSource:
        if fact.opcode != 1 or not fact.ending or
            f.handlers[int(node)] != flatCachedJump[1]: return false
        dirty = f.arguments[int(node)].y
      else:
        if fact.ending or not fact.fallthrough or not supportedArmOpcode(fact.opcode): return false
        inc pure
      inc node
    if pure == 0 or dirty == flatStop or int(dirty) >= f.handlers.len or
        f.handlers[int(dirty)] != flatArmDirtyLoop or not flatArmDirtyShape(f, dirty): return false
    let dirtyCharge = f.arguments[int(dirty)]
    if not armDirtyLoopChargeMatches(jit, dirty, dirtyCharge.y, dirtyCharge.x): return false
    let dirtyArms = f.arguments[int(dirty+5)]
    let yes = uint32(dirtyArms.x shr 32)
    let no = dirtyArms.y
    if not ((yes == dirty and no == tail) or (no == dirty and yes == tail)): return false
    let terminal = armEnding(jit, readEntry)
    if terminal <= readEntry or int(terminal) >= f.sites.len or not flatArmCachedBranch(f, terminal):
      return false
    let readFact = f.plan.facts[int(f.sites[int(readEntry)])]
    if readFact.opcode notin {52'u8..58'u8}: return false
    let tailCharge = f.arguments[int(tail)]
    if uint64(f.sites[int(tail)])+uint64(tailCharge.y) != uint64(f.sites[int(terminal)])+1:
      return false
    let arms = f.arguments[int(terminal)]
    let left = uint32(arms.x shr 32)
    let right = arms.y
    if (left == prefix) == (right == prefix): return false
    let outside = if left == prefix: right else: left
    if outside == dirty or outside == tail: return false
    var body = newArmRegionBody()
    for ordinal in uint64(first)..<endingSource-1:
      let fact = f.plan.facts[int(ordinal)]
      if fact.opcode == 2: continue
      emitArmOperation(body, fact.opcode, fact.args.slots, fact.args.x)
    item = ArmMemoryCycleBlock(prefixHeader: prefix, dirtyHeader: dirty, tailHeader: tail,
      tailEntry: readEntry, other: outside,
      prefixSpan: prefixCharge.y, tailSpan: tailCharge.y, prefixOperations: pure+1,
      tailOperations: terminal-readEntry+1, prefixPrice: prefixCharge.x,
      tailPrice: tailCharge.x, prefixBody: move(body),
      dirty: flatArmDirtyBody(f, dirty),
      dirtyBaseSlot: f.plan.facts[int(f.sites[int(dirty+2)])].args.slots.bIndex,
      dirtyDisplacement: uint32(f.plan.facts[int(f.sites[int(dirty+2)])].args.x and 0xffffffff'u64),
      dirtyWord: flatArmWordShape(f, dirty), tailRead: flatArmReadBody(f, readEntry, terminal))
    true

  proc flatArmMemoryCycle(f: var FlatFrame, offset: uint32): uint32 =
    ## All native pointers belong only to this call; unstarted headers use their original checked reservations.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    let prefix = armMemoryCycleHeader(jit, 0)
    let dirty = armMemoryCycleHeader(jit, 1)
    let tail = armMemoryCycleHeader(jit, 2)
    assert offset == prefix
    let prefixCharge = f.arguments[int(prefix)]
    let dirtyCharge = f.arguments[int(dirty)]
    let tailCharge = f.arguments[int(tail)]
    if f.pricingKind != 0 or f.barrier != flatStop or f.info.blockCharged or offset != prefix or
        not armMemoryCycleChargeMatches(jit, 0, prefix, prefixCharge.y, prefixCharge.x) or
        not armMemoryCycleChargeMatches(jit, 1, tail, tailCharge.y, tailCharge.x) or
        not armDirtyLoopChargeMatches(jit, dirty, dirtyCharge.y, dirtyCharge.x):
      let original = f.armOriginal[int(prefix)]
      assert original != nil
      if original != nil: return original(f, offset)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    var state = [uint64(f.info.gas), f.remaining, 0'u64, 0'u64, 0'u64, 0'u64, 0'u64,
      0'u64, 0'u64, 0'u64, 0'u64, 0'u64, 0'u64, uint64(flatStop)]
    let destination = callArmMemoryCycleContext(jit, f.info.registers, f.armMemory, f.dirtyPages, state)
    f.info.gas = MachineGas(state[0])
    f.remaining = state[1]
    f.info.blockCharged = false
    if state[13] != uint64(flatStop):
      assert state[13] == uint64(prefix) or state[13] == uint64(dirty) or state[13] == uint64(tail)
      f.reservation = uint32(state[13]) or flatReservationHeaderFlag
    assert int(destination) < f.handlers.len
    if int(destination) >= f.handlers.len: return flatLocal(f, offset,
        oracle.StepError.InvalidPreparedProgram)
    if destination == prefix:
      let original = f.armOriginal[int(prefix)]
      assert original != nil
      if original != nil: return original(f, prefix)
      return flatLocal(f, prefix, oracle.StepError.InvalidPreparedProgram)
    if destination == dirty: return flatArmCheckedTail(f, dirty)
    if destination == tail: return flatCharge(f, tail)
    destination

  type FlatArmMacroHeader = object
    first, last, span: uint32
    price: uint64

  func flatArmMacroHeader(f: FlatFrame, offset: uint32,
      header: var FlatArmMacroHeader): bool =
    ## A known header handler binds its source span even when leading noops have no body node.
    if uint64(offset)+1 >= uint64(f.handlers.len) or int(offset)+1 >= f.sites.len: return false
    var source = default(FlatSourceInterval)
    # The first prototype admits one bounded observed graph; larger source spans retain ordinary dispatch.
    if not flatSourceIntervalAt(f, offset, 64, source): return false
    for current in source.first..<source.last:
      if f.plan.facts[int(current)].ending: return false
    let body = f.sites[int(offset)+1]
    if body < source.first or body > source.last: return false
    for skipped in source.first..<body:
      let fact = f.plan.facts[int(skipped)]
      if fact.opcode != 2 or fact.ending: return false
    header = FlatArmMacroHeader(first: source.first, last: source.last, span: source.span,
      price: source.price)
    true

  func flatArmMacroRead(f: FlatFrame, jit: ArmJit, offset: uint32,
      shape: var ArmMacroShape): bool =
    var source = default(FlatArmMacroHeader)
    if not flatArmMacroHeader(f, offset, source) or f.handlers[int(offset)] != flatCharge or
        f.plan.facts[int(source.last)].opcode != 1: return false
    let body = offset+1
    if f.handlers[int(body)] != flatArmMemory: return false
    let entry = armMacroChildRecord(jit, body)
    if entry.code < 2 or int(entry.ending) >= f.handlers.len or
        entry.ending <= body or f.handlers[int(entry.ending)] != flatCachedJump[1] or
        f.sites[int(entry.ending)] != source.last: return false
    var nextSource = source.first
    var operations = 0'u32
    var reads = 0'u32
    for current in body..<entry.ending:
      if int(current) >= f.sites.len: return false
      let site = f.sites[int(current)]
      if site < nextSource or site >= source.last: return false
      for skipped in nextSource..<site:
        let fact = f.plan.facts[int(skipped)]
        if fact.opcode != 2 or fact.ending: return false
      let fact = f.plan.facts[int(site)]
      if fact.ending or not fact.fallthrough: return false
      if fact.opcode in {52'u8..58'u8, 124'u8..130'u8}:
        inc reads
      elif not supportedArmOpcode(fact.opcode):
        return false
      inc operations
      nextSource = site+1
    for skipped in nextSource..<source.last:
      let fact = f.plan.facts[int(skipped)]
      if fact.opcode != 2 or fact.ending: return false
    if reads < 2 or operations < 4 or operations != entry.operations: return false
    let target = f.arguments[int(entry.ending)].y
    if target != shape.cycleHeader: return false
    shape.readHeader = offset
    shape.readBody = body
    shape.readTerminal = entry.ending
    shape.terminalTarget = target
    shape.readSpan = source.span
    shape.readPrice = source.price
    true

  func flatArmMacroBranch(f: FlatFrame, jit: ArmJit, offset: uint32,
      shape: var ArmMacroShape): bool =
    var source = default(FlatArmMacroHeader)
    if not flatArmMacroHeader(f, offset, source) or source.span != 1 or
        f.handlers[int(offset)] != flatCharge or
        f.plan.facts[int(source.first)].opcode != 88: return false
    let body = offset+1
    if f.sites[int(body)] != source.first or f.handlers[int(body)] != flatBranch[88]:
      return false
    let args = f.arguments[int(body)]
    let yes = uint32(args.x shr 32)
    let no = args.y
    if int(yes) >= f.handlers.len or int(no) >= f.handlers.len or yes == no: return false
    var read = flatStop
    if yes == shape.pureHeader: read = no
    elif no == shape.pureHeader: read = yes
    else: return false
    if not flatArmMacroRead(f, jit, read, shape): return false
    shape.branchHeader = offset
    shape.branchYes = yes
    shape.branchNo = no
    shape.branchSlot = args.slots.aIndex
    shape.branchImmediate = flatSext32(uint32(args.x and 0xffffffff'u64))
    shape.branchSpan = source.span
    shape.branchPrice = source.price
    true

  proc flatArmMacroDiscover(f: FlatFrame, shape: var ArmMacroShape): bool {.noinline.} =
    ## ABI-tagged existing children and genuine cached source edges define one small closed graph.
    if f.pricingKind != 0 or not f.plan.allowNative: return false
    let jit {.cursor.} = f.armJit
    if jit == nil or armMemoryCycleStatus(jit) != 2 or
        not armResidentMemoryCycleActive(jit): return false
    let cycle = armMemoryCycleHeader(jit, 0)
    let dirty = armMemoryCycleHeader(jit, 1)
    let tail = armMemoryCycleHeader(jit, 2)
    var cycleSource = default(FlatArmMacroHeader)
    var dirtySource = default(FlatArmMacroHeader)
    var tailSource = default(FlatArmMacroHeader)
    if not flatArmMacroHeader(f, cycle, cycleSource) or
        not flatArmMacroHeader(f, dirty, dirtySource) or
        not flatArmMacroHeader(f, tail, tailSource): return false
    if not armMemoryCycleChargeMatches(jit, 0, cycle, cycleSource.span, cycleSource.price) or
        not armMemoryCycleChargeMatches(jit, 1, tail, tailSource.span, tailSource.price) or
        not armDirtyLoopChargeMatches(jit, dirty, dirtySource.span,
            dirtySource.price): return false
    let outside = armMacroCycleExit(jit)
    var staticSource = default(FlatArmMacroHeader)
    if not flatArmMacroHeader(f, outside, staticSource) or staticSource.span != 1 or
        f.handlers[int(outside)] != flatCharge or
        f.plan.facts[int(staticSource.first)].opcode != 40: return false
    let jump = outside+1
    if f.sites[int(jump)] != staticSource.first or
        f.handlers[int(jump)] != flatCachedJump[40]: return false
    let pure = f.arguments[int(jump)].y
    var pureSource = default(FlatArmMacroHeader)
    if not flatArmMacroHeader(f, pure, pureSource) or pureSource.span != 3 or
        f.handlers[int(pure)] != flatArmWhole: return false
    if f.plan.facts[int(pureSource.first)].opcode != 131 or
        f.plan.facts[int(pureSource.first)+1].opcode != 149 or
        f.plan.facts[int(pureSource.last)].opcode != 81: return false
    let body = pure+1
    let terminal = pure+3
    if int(terminal) >= f.handlers.len or f.sites[int(body)] != pureSource.first or
        f.sites[int(pure)+2] != pureSource.first+1 or
        f.sites[int(terminal)] != pureSource.last or
        f.handlers[int(body)] != flatArmBranch or
        f.handlers[int(terminal)] != flatBranch[81]: return false
    let native = armMacroChildRecord(jit, body)
    if native.code < 2 or native.operations != 3 or native.ending != terminal: return false
    let args = f.arguments[int(terminal)]
    let yes = uint32(args.x shr 32)
    let no = args.y
    if yes == no or int(yes) >= f.handlers.len or int(no) >= f.handlers.len: return false
    var base = ArmMacroShape(cycleHeader: cycle, cycleExit: outside,
      staticHeader: outside, staticTarget: pure, pureHeader: pure, pureBody: body,
      pureTerminal: terminal, pureYes: yes, pureNo: no, staticSpan: staticSource.span,
      pureSpan: pureSource.span, staticPrice: staticSource.price, purePrice: pureSource.price)
    var found = false
    for target in [yes, no]:
      var candidate = base
      if flatArmMacroBranch(f, jit, target, candidate):
        if found: return false
        shape = candidate
        found = true
    if not found: return false
    let headers = [cycle, dirty, tail, outside, pure, shape.branchHeader, shape.readHeader]
    for first in 0..<headers.len:
      for second in first+1..<headers.len:
        if headers[first] == headers[second]: return false
    let rare = if shape.pureYes == shape.branchHeader: shape.pureNo else: shape.pureYes
    for header in headers:
      if rare == header: return false
    true

  proc flatArmMacroPureBody(f: FlatFrame, shape: ArmMacroShape,
      body: var ArmBlock): bool {.noinline.} =
    ## Rebuild the existing pure child's source operations and conditional from sealed facts.
    if shape.pureBody >= shape.pureTerminal or int(shape.pureTerminal) >= f.sites.len:
      return false
    body = default(ArmBlock)
    for current in shape.pureBody..<shape.pureTerminal:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.ending or not fact.fallthrough or not supportedArmOpcode(fact.opcode):
        return false
      emitArmOperation(body, fact.opcode, fact.args.slots, fact.args.x)
    let terminal = f.plan.facts[int(f.sites[int(shape.pureTerminal)])]
    let args = f.arguments[int(shape.pureTerminal)]
    if not terminal.ending or terminal.opcode notin {81'u8..90'u8, 170'u8..175'u8}:
      return false
    emitArmBranch(body, terminal.opcode, args.slots,
        flatSext32(uint32(args.x and 0xffffffff'u64)), uint32(args.x shr 32), args.y)
    true

  proc flatArmMacro(f: var FlatFrame, offset: uint32): uint32 =
    ## One native call owns no frame capability; canonical replay starts only after all borrows end.
    var shape = default(ArmMacroShape)
    var dirty = flatStop
    var tail = flatStop
    var destination = flatStop
    var admitted = false
    var state = default(ArmMacroState)
    state[0] = uint64(f.info.gas)
    state[1] = f.remaining
    state[13] = uint64(flatStop)
    state[24] = uint64(flatStop)
    block:
      let jit {.cursor.} = f.armJit
      if jit != nil and armMacroStatus(jit) == 2:
        shape = armMacroShape(jit)
        dirty = armMemoryCycleHeader(jit, 1)
        tail = armMemoryCycleHeader(jit, 2)
        let headers = [shape.cycleHeader, dirty, tail, shape.staticHeader,
          shape.pureHeader, shape.branchHeader, shape.readHeader]
        var complete = true
        for header in headers:
          if int(header) >= f.arguments.len: complete = false
        if complete and f.pricingKind == 0 and f.barrier == flatStop and
            not f.info.blockCharged and offset == shape.cycleHeader:
          let prefixCharge = f.arguments[int(shape.cycleHeader)]
          let dirtyCharge = f.arguments[int(dirty)]
          let tailCharge = f.arguments[int(tail)]
          if armMemoryCycleChargeMatches(jit, 0, shape.cycleHeader, prefixCharge.y,
              prefixCharge.x) and armMemoryCycleChargeMatches(jit, 1, tail,
              tailCharge.y, tailCharge.x) and armDirtyLoopChargeMatches(jit, dirty,
              dirtyCharge.y, dirtyCharge.x):
            var current = shape
            current.staticSpan = f.arguments[int(shape.staticHeader)].y
            current.staticPrice = f.arguments[int(shape.staticHeader)].x
            current.pureSpan = f.arguments[int(shape.pureHeader)].y
            current.purePrice = f.arguments[int(shape.pureHeader)].x
            current.branchSpan = f.arguments[int(shape.branchHeader)].y
            current.branchPrice = f.arguments[int(shape.branchHeader)].x
            current.readSpan = f.arguments[int(shape.readHeader)].y
            current.readPrice = f.arguments[int(shape.readHeader)].x
            let staticBody = shape.staticHeader+1
            let branchBody = shape.branchHeader+1
            if int(staticBody) < f.arguments.len and int(branchBody) < f.arguments.len and
                int(shape.pureTerminal) < f.arguments.len and
                int(shape.readTerminal) < f.arguments.len:
              current.staticTarget = f.arguments[int(staticBody)].y
              current.pureYes = uint32(f.arguments[int(shape.pureTerminal)].x shr 32)
              current.pureNo = f.arguments[int(shape.pureTerminal)].y
              current.branchYes = uint32(f.arguments[int(branchBody)].x shr 32)
              current.branchNo = f.arguments[int(branchBody)].y
              current.branchSlot = f.arguments[int(branchBody)].slots.aIndex
              current.branchImmediate = flatSext32(uint32(
                  f.arguments[int(branchBody)].x and 0xffffffff'u64))
              current.terminalTarget = f.arguments[int(shape.readTerminal)].y
            else:
              complete = false
            if complete and armMacroMatches(jit, current):
              destination = callArmMacroContext(jit, f.info.registers, f.armMemory, f.dirtyPages, state)
              admitted = true
    if not admitted: return flatArmMemoryCycle(f, offset)
    when defined(pvmArmMacroStateTrace):
      f.armMacroLastState = state
    f.info.gas = MachineGas(state[0])
    f.remaining = state[1]
    f.info.blockCharged = false
    if state[24] != uint64(flatStop):
      var known = false
      for header in [shape.cycleHeader, dirty, tail, shape.staticHeader,
          shape.pureHeader, shape.branchHeader, shape.readHeader]:
        if state[24] == uint64(header): known = true
      assert known
      if not known: return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
      f.reservation = uint32(state[24]) or flatReservationHeaderFlag
    assert int(destination) < f.handlers.len
    if int(destination) >= f.handlers.len: return flatLocal(f, offset,
      oracle.StepError.InvalidPreparedProgram)
    if destination == shape.cycleHeader:
      let original = f.armOriginal[int(shape.cycleHeader)]
      assert original != nil
      if original != nil: return original(f, shape.cycleHeader)
      return flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)
    if destination == dirty: return flatArmCheckedTail(f, dirty)
    if destination == tail: return flatCharge(f, tail)
    destination

  when defined(pvmArmMacroReceipt):
    proc flatArmRefuseResidentCycleReceipt*(f: var FlatFrame) =
      ## Exercise actual source discovery, linked publication and Frame handler installation.
      assert f.plan.allowNative
      if f.armJit == nil: f.armJit = newArmJit(clippedReads = true)
      let jit {.cursor.} = f.armJit
      assert jit != nil
      if jit != nil: armRefuseResidentCycleReceipt(jit)

    func flatArmMacroStatistics*(f: FlatFrame): array[7, uint64] =
      ## Receipt-only copied activity proves actual joined execution independently of guest results.
      let jit {.cursor.} = f.armJit
      if jit == nil: default(array[7, uint64])
      else: armMacroStatistics(jit)

    func flatArmMacroResidentActive*(f: FlatFrame): bool =
      ## Receipt-only kind evidence distinguishes a resident image from linked fallback.
      let jit {.cursor.} = f.armJit
      jit != nil and armMacroResidentActive(jit)

    func flatArmMacroImageWords*(f: FlatFrame): uint32 =
      ## Receipt-only length proves the emitted image stayed under the bounded word limit.
      let jit {.cursor.} = f.armJit
      if jit == nil: 0'u32 else: armMacroImageWords(jit)

    when defined(pvmArmMacroStateTrace):
      func flatArmMacroLastState*(f: FlatFrame): ArmMacroState =
        ## Copy the last native macro return state for complete linked/resident comparison.
        f.armMacroLastState

  proc flatArmMacroProbe(f: var FlatFrame, offset: uint32): uint32 =
    ## Eight real cycle exits bound the cold search; a refusal keeps every existing child usable.
    let eligible = f.pricingKind == 0 and f.barrier == flatStop and not f.info.blockCharged
    let destination = flatArmMemoryCycle(f, offset)
    if not eligible or destination == flatStop or f.reason != oracle.StepError.None:
      return destination
    var decide = false
    block:
      let jit {.cursor.} = f.armJit
      if jit != nil and armResidentMemoryCycleActive(jit) and
          armMacroStatus(jit) == 0 and destination == armMacroCycleExit(jit):
        decide = armMacroProbeReady(jit)
    if not decide: return destination
    let before = armClock()
    var shape = default(ArmMacroShape)
    let matched = flatArmMacroDiscover(f, shape)
    var published = false
    block:
      let jit {.cursor.} = f.armJit
      if jit != nil:
        if matched:
          var cycle = default(ArmMemoryCycleBlock)
          var pure = default(ArmBlock)
          var read = default(ArmReadSpan)
          let tail = armMemoryCycleHeader(jit, 2)
          if tail < high(uint32) and
              flatArmMemoryCycleShape(f, tail+1, shape.cycleHeader, cycle,
                  flatArmMacroProbe) and cycle.other == shape.staticHeader and
              flatArmMacroPureBody(f, shape, pure) and
              flatArmReadSpanBody(f, shape.readBody, shape.readTerminal, read):
            published = publishArmResidentMacro(jit, shape, cycle, pure, read)
          if not published: published = publishArmMacro(jit, shape)
        else: refuseArmMacro(jit)
        jit.compilationNs+=armClock()-before
    if published: f.handlers[int(offset)] = flatArmMacro
    else: f.handlers[int(offset)] = flatArmMemoryCycle
    destination

  proc flatArmTryMemoryCycle(f: var FlatFrame, readEntry, prefix: uint32) {.noinline.} =
    ## Existing hot child publication proves observation; one bounded source graph can install a driver.
    let jit = f.armJit
    if jit == nil or armMemoryCycleStatus(jit) != 0: return
    var item = default(ArmMemoryCycleBlock)
    if not flatArmMemoryCycleShape(f, readEntry, prefix, item): return
    let before = armClock()
    let published = if publishArmResidentMemoryCycle(jit, item): true
      else: publishArmMemoryCycle(jit, item)
    jit.compilationNs+=armClock()-before
    if not published: return
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    assert f.handlers[int(prefix)] == flatCharge
    f.armOriginal[int(prefix)] = f.handlers[int(prefix)]
    f.handlers[int(prefix)] = if armResidentMemoryCycleActive(jit): flatArmMacroProbe
      else: flatArmMemoryCycle

  proc flatArmMemoryCycleStatistics*(f: FlatFrame): array[6, uint64] =
    ## Copied diagnostics separate outer bridges from nested child visits and word groups.
    let jit = f.armJit
    if jit == nil: default(array[6, uint64])
    else: armMemoryCycleStatistics(jit)

  proc flatArmResidentMemoryCycleActive*(f: FlatFrame): bool =
    ## Copied diagnostics prove the resident emitter ran instead of the linked fallback.
    let jit = f.armJit
    if jit == nil: false
    else: armResidentMemoryCycleActive(jit)

  proc flatArmReadBranch(f: var FlatFrame, offset: uint32): uint32 =
    ## End every descriptor/register borrow before discovering a source graph or using checked fallback.
    var destination = flatStop
    var discover = false
    if f.barrier == flatStop:
      block:
        let jit {.cursor.} = f.armJit
        assert jit != nil
        if jit != nil:
          let ending = armEnding(jit, offset)
          let args = f.arguments[int(ending)]
          destination = callArmMemoryBranchContext(jit, offset, uint32(args.x shr 32), args.y,
            f.info.registers, f.armMemory)
          discover = armMemoryCycleStatus(jit) == 0
    if destination != flatStop:
      assert int(destination) < f.handlers.len
      f.info.blockCharged = false
      if discover: flatArmTryMemoryCycle(f, offset, destination)
      return destination
    let original = f.armOriginal[int(offset)]
    assert original != nil
    if original != nil: return original(f, offset)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmReadBody(f: FlatFrame, offset, ending: uint32): ArmReadSpan {.noinline.} =
    ## Rebuild the same admitted direct-read, pure suffix and cached branch IR.
    let first = f.plan.facts[int(f.sites[int(offset)])]
    let readOpcode = int(first.opcode)
    assert readOpcode >= 52 and readOpcode <= 58
    var native = default(ArmReadSpan)
    armUseClippedReads(native, f.armJit)
    emitArmDirectRead(native, first.args.slots, uint32(first.args.x and 0xffffffff'u64),
        range[52..58](readOpcode))
    for current in offset+1..<ending:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      assert supportedArmOpcode(fact.opcode)
      emitArmReadArithmetic(native, fact.opcode, fact.args.slots, fact.args.x)
    let branch = f.plan.facts[int(f.sites[int(ending)])]
    let args = f.arguments[int(ending)]
    emitArmReadBranch(native, branch.opcode, args.slots,
        flatSext32(uint32(args.x and 0xffffffff'u64)), uint32(args.x shr 32), args.y)
    move(native)

  proc flatArmUpgradeReadBranch(f: var FlatFrame, offset: uint32): bool =
    ## Rebuild one direct-load prefix only after the original conditional has cached both positive arms.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return false
    let ending = armEnding(jit, offset)
    let before = armClock()
    let native = flatArmReadBody(f, offset, ending)
    var words = armReadInstructionsForOwner(jit, native, ending, true)
    if words.len >= 1024: return false
    let published = publishArmEntry(jit, offset, ending, ending-offset+1, words)
    jit.compilationNs+=armClock()-before
    if not published: return false
    f.handlers[int(offset)] = flatArmReadBranch
    true

  proc flatArmPendingReadBranch(f: var FlatFrame, offset: uint32): uint32 =
    ## Keep the original checked pair until the branch arms are valid; a failed publication retires the probe.
    let jit = f.armJit
    assert jit != nil
    let original = f.armOriginal[int(offset)]
    assert original != nil
    if jit != nil and f.barrier == flatStop and flatArmCachedBranch(f, armEnding(jit, offset)):
      if flatArmUpgradeReadBranch(f, offset): return flatArmReadBranch(f, offset)
      if original != nil: f.handlers[int(offset)] = original
    if original != nil: return original(f, offset)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmCompileDirectReadBranch(f: var FlatFrame, offset: uint32): uint32 =
    ## Defer one direct load and pure suffix ending in a conditional, avoiding a superseded branch publication.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return offset
    var ending = offset+1
    var count = 1'u32
    while int(ending) < f.sites.len and count < 64:
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]:
        break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough or not supportedArmOpcode(fact.opcode): break
      inc ending
      inc count
    if count < 2 or int(ending) >= f.sites.len: return offset
    let terminal = f.plan.facts[int(f.sites[int(ending)])]
    if terminal.opcode notin {81'u8..90'u8, 170'u8..175'u8} or not terminal.ending:
      return offset
    armPendingMemoryEnding(jit, offset, ending)
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmPendingReadBranch
    ending+1

  proc flatArmReadSpanBody(f: FlatFrame, offset, ending: uint32,
      native: var ArmReadSpan): bool {.noinline.} =
    ## Reconstruct the standalone child's exact guarded window or individual-read body from source.
    if ending <= offset or ending-offset > 64 or int(ending) > f.sites.len: return false
    var written = 0'u32
    var window = true
    let base = f.plan.facts[int(f.sites[int(offset)])].args.slots.bIndex
    var first = high(uint32)
    var last = 0'u32
    var reads = 0'u32
    for current in offset..<ending:
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.ending or not fact.fallthrough: return false
      if fact.opcode in 124'u8..130'u8:
        let displacement = uint32(fact.args.x and 0xffffffff'u64)
        if fact.opcode != 130: window = false # Narrow/signed reads retain their own individual guards, never the scaled word window.
        if fact.args.slots.bIndex != base or (written and (1'u32 shl int(base))) != 0:
          window = false # Derived or overwritten address bases retain the accepted individual guards.
        if displacement < first: first = displacement
        if displacement > last: last = displacement
        written = written or (1'u32 shl int(fact.args.slots.aIndex))
        inc reads
      elif supportedArmOpcode(fact.opcode):
        written = written or (1'u32 shl int(fact.args.slots.destinationIndex))
      else: return false
    if reads < 2 or ending-offset < 4: return false
    if last-first > 4088: window = false
    native = default(ArmReadSpan)
    if window:
      # Relative scaled loads need equal low displacement bits; the initial effective address may still be unaligned.
      for current in offset..<ending:
        let fact = f.plan.facts[int(f.sites[int(current)])]
        if fact.opcode == 130 and (uint32(fact.args.x and 0xffffffff'u64)-first) mod 8 != 0:
          window = false
    if window: beginArmReadWindow(native, base, first, last)
    else: armUseClippedReads(native, f.armJit)
    for current in offset..<ending:
      # Only a proved stable base uses the shared window; all other mixed spans preserve their original lowering.
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.opcode in 124'u8..130'u8:
        let displacement = uint32(fact.args.x and 0xffffffff'u64)
        if window: emitArmWindowRead(native, fact.args.slots.aIndex, displacement-first)
        else:
          # Restate the sealed source predicate on a local scalar before the closed opcode conversion.
          let readOpcode = int(fact.opcode)
          assert readOpcode >= 124 and readOpcode <= 130
          emitArmRead(native, fact.args.slots, displacement, range[124..130](readOpcode))
      else:
        emitArmReadArithmetic(native, fact.opcode, fact.args.slots, fact.args.x)
    true

  proc flatArmCompileReadSpan(f: var FlatFrame, offset: uint32): uint32 =
    ## Combine multiple selected-width reads and pure arithmetic within one already-reserved source block.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return offset
    var ending = offset
    var count = 0'u32
    var reads = 0'u32
    while int(ending) < f.sites.len and count < 64:
      # Headers, stores, branches, hosts and every observable exit end the speculative prefix.
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]: break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough: break
      if fact.opcode in 124'u8..130'u8: inc reads
      elif not supportedArmOpcode(fact.opcode): break
      inc ending
      inc count
    if reads < 2 or count < 4: return offset
    var native = default(ArmReadSpan)
    if not flatArmReadSpanBody(f, offset, ending, native): return offset
    var words = armReadInstructionsForOwner(jit, native, ending)
    if words.len >= 1024: return offset # Oversized spans retain the accepted first-read leaf, without poisoning its admission.
    if not publishArmEntry(jit, offset, ending, count, words): return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmMemory
    ending

  proc flatArmCompileMemory(f: var FlatFrame, offset: uint32): uint32 =
    ## Admit a first selected-width indirect read with at least three pure suffix operations, preserving every source coordinate.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return offset
    var native = default(ArmBlock)
    var ending = offset+1
    var count = 1'u32
    while int(ending) < f.sites.len and count < 64:
      # Duplicate header sites, branches and all further memory/host/error boundaries stop the arithmetic suffix.
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]: break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough or not supportedArmOpcode(fact.opcode): break
      emitArmOperation(native, fact.opcode, fact.args.slots, fact.args.x)
      inc ending
      inc count
    if int(ending) < f.sites.len and f.plan.facts[int(f.sites[int(ending)])].opcode in
        124'u8..130'u8:
      # Only an encountered second admitted read can justify the transactional span builder.
      let combined = flatArmCompileReadSpan(f, offset)
      if combined != offset: return combined
    if count < 4:
      refuseArmEntry(jit, offset)
      return offset
    let args = f.arguments[int(offset)]
    let readOpcode = int(f.plan.facts[int(f.sites[int(offset)])].opcode)
    assert readOpcode >= 124 and readOpcode <= 130 # The caller admitted a sealed load; keep its conversion proof local.
    var words = armMemoryInstructionsForOwner(jit, native, args.slots, uint32(args.x and
        0xffffffff'u64), ending,
      range[124..130](readOpcode))
    if not publishArmEntry(jit, offset, ending, count, words): return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmMemory
    ending

  proc flatArmCompilePrefixReadSpan(f: var FlatFrame, offset: uint32): uint32 {.noinline.} =
    ## One speculative read-only register span can include its already admitted arithmetic prefix.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return offset
    var native = default(ArmReadSpan)
    armUseClippedReads(native, jit)
    var ending = offset
    var count = 0'u32
    var reads = 0'u32
    while int(ending) < f.sites.len and count < 64:
      # Keep the existing charge/header and source-terminal boundaries intact.
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]: break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough: break
      let displacement = uint32(fact.args.x and 0xffffffff'u64)
      if fact.opcode in 52'u8..58'u8:
        emitArmDirectRead(native, fact.args.slots, displacement, range[52..58](int(fact.opcode)))
        inc reads
      elif fact.opcode in 124'u8..130'u8:
        emitArmRead(native, fact.args.slots, displacement, range[124..130](int(fact.opcode)))
        inc reads
      elif supportedArmOpcode(fact.opcode):
        emitArmReadArithmetic(native, fact.opcode, fact.args.slots, fact.args.x)
      else:
        break # Stores, host work and unsupported semantics keep the complete original prefix.
      inc ending
      inc count
    if reads == 0 or count < 4: return offset
    var words = armReadInstructionsForOwner(jit, native, ending)
    if words.len >= 1024: return offset # Preserve the existing pure publisher on bounded refusal.
    if jit.fragments >= 8191 or jit.codeBytes > 1048576 or
        uint64(words.len+1)*4 > 1048576-jit.codeBytes:
      return offset # A smaller original pure leaf may still fit; do not mutate its refusal record.
    if not publishArmEntry(jit, offset, ending, count, words): return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmMemory
    ending

  proc flatArmCompile(f: var FlatFrame, offset: uint32): uint32 =
    ## Compilation happens only during lazy stream emission, never as a universal dispatch probe.
    if f.armJit == nil: f.armJit = newArmJit(clippedReads = true)
    let jit = f.armJit
    if jit == nil: return offset
    let entry = armEntry(jit, offset, uint32(f.handlers.len))
    if entry != 0: return offset
    if int(offset)+1 < f.sites.len and f.sites[int(offset)] == f.sites[int(offset)+1]: return offset
    if f.plan.facts[int(f.sites[int(offset)])].opcode in 52'u8..58'u8:
      return flatArmCompileDirectReadBranch(f, offset)
    if f.plan.facts[int(f.sites[int(offset)])].opcode in
        124'u8..130'u8: return flatArmCompileMemory(f, offset)
    var native = default(ArmBlock)
    var ending = offset
    var count = 0'u32
    while int(ending) < f.handlers.len and count < 64:
      # Headers share their source site with the immediately following operation; never bypass charging.
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]: break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough or not supportedArmOpcode(fact.opcode): break
      emitArmOperation(native, fact.opcode, fact.args.slots, fact.args.x)
      inc ending
      inc count
    let terminal = if int(ending) < f.sites.len:
        f.plan.facts[int(f.sites[int(ending)])].opcode else: 0'u8
    if count > 0 and (terminal in 52'u8..58'u8 or terminal in 124'u8..130'u8):
      # A failed speculative admission leaves the established pure leaf available below.
      let combined = flatArmCompilePrefixReadSpan(f, offset)
      if combined > offset: return combined
    # Short conditional suffixes can fuse their checked header after genuine branch admission.
    # Other short leaves retain the original floor; isolated calls would add an extra native transition.
    if count < 4 and (count == 0 or terminal notin {81'u8..90'u8, 170'u8..175'u8}):
      refuseArmEntry(jit, offset)
      return offset
    var words = armInstructions(native)
    let published = publishArmEntry(jit, offset, ending, count, words)
    if not published: return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = if terminal in {81'u8..90'u8,
        170'u8..175'u8}: flatArmPending else: flatArmExecute
    ending

  proc flatArmPrepare(f: var FlatFrame, origin: uint32) =
    ## Only newly emitted suffix nodes are examined. Unsupported nodes keep the ordinary hot loop unchanged.
    if not f.plan.allowNative: return # Decide before scanning, allocating storage or consulting a native cache.
    let before = armClock()
    var offset = origin
    while int(offset) < f.handlers.len:
      let ending = flatArmCompile(f, offset)
      offset = if ending > offset: ending else: offset+1
    for candidate in origin..<uint32(f.handlers.len): flatArmTryMixedProbe(f, candidate)
    let jit = f.armJit
    if jit != nil: jit.compilationNs+=armClock()-before

  proc flatArmStatistics*(f: FlatFrame): array[5, uint64] =
    ## Explicit native coverage counters distinguish compilation, reuse, lowered operations and emitted bytes.
    if f.armJit == nil: default(array[5, uint64])
    else: [f.armJit.fragments, f.armJit.calls, f.armJit.operations, f.armJit.codeBytes,
        f.armJit.compilationNs]

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  proc flatArmControlStatistics*(f: FlatFrame): array[2, uint64] =
    ## Native branch and checked-header entries prove the new control path executed.
    if f.armJit == nil: default(array[2, uint64])
    else: [f.armJit.branchCalls, f.armJit.headerCalls]

proc flatResumePaid(f: var FlatFrame, body: uint32, start: int): uint32 =
  ## Only an actual paid execution entry reserves its cached body; target prelinking never calls this helper.
  assert f.info.blockCharged and f.remaining > 0 and f.barrier == flatStop
  assert start >= 0 and start < f.plan.facts.len
  assert int(body) < f.handlers.len and int(body) < f.sites.len
  let count = f.plan.facts[start].sourceCount
  assert count > 0 and uint64(start)+uint64(count) <= uint64(f.plan.facts.len)
  assert uint64(f.sites[int(body)]) >= uint64(start) and
    uint64(f.sites[int(body)]) < uint64(start)+uint64(count)
  let reserved = min(f.remaining, uint64(count))
  f.remaining-=reserved
  f.reservation = uint32(start)+uint32(reserved)
  if reserved < uint64(count):
    # Folded noops may precede this body: stop at their exact source fact, not the next physical node's PC.
    f.barrierFact = f.reservation
    var boundary = body
    while int(boundary) < f.sites.len and f.sites[int(boundary)] < f.barrierFact:
      inc boundary
    assert int(boundary) < f.handlers.len
    assert uint64(f.sites[int(boundary)]) < uint64(start)+uint64(count)
    f.barrier = boundary
    f.savedHandler = f.handlers[int(boundary)]
    f.handlers[int(boundary)] = flatBudget
  body

proc runFlat*(f: var FlatFrame, limit: uint64) =
  ## The offset-returning dispatch reserves attempts at complete headers or actual paid cached-body entries.
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.remaining = limit
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.barrier = flatStop
  f.savedHandler = nil
  f.attemptedExit = false
  when defined(pvmX86Jit):
    f.x86PreviousValid = false
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # No observed edge can bridge an invocation or host stop; cached code itself remains source-owned.
    f.armPreviousValid = false
  if limit == 0:
    f.reason = oracle.StepError.StepLimitExceeded
    return
  if f.plan == nil:
    f.reason = oracle.StepError.InvalidMachine
    return
  if f.plan.singleStep:
    # Bounded adapter plans carry no whole-program maps and cannot authorize an ordinary invocation.
    f.reason = oracle.StepError.InvalidPreparedProgram
    return
  if f.preparationFailure != FlatError.None:
    f.reason = oracle.StepError.InvalidPreparedProgram
    return
  when defined(pvmX86Jit) and not defined(pvmX86WideManualProof):
    # A reset or same-plan stream lease supplies an uncharged cold boundary after warmup.
    flatX86ColdWideAdmission(f, flatStop)
  f.dynamicOffsets = default(array[256, uint64]) # Invocation reset remains inside execution timing.
  let pc = uint32(uint64(f.info.pc) and 0xffffffff'u64)
  var offset = flatStop
  if f.info.blockCharged and uint64(pc) < uint64(f.plan.factAt.len) and f.compiledForPc.len > 0:
    # Only real entry/resumption may reserve a paid interior body; branch prelinking keeps the original resolver.
    let packed = f.compiledForPc[int(pc)]
    if packed != 0:
      let target = packed-1
      if (target and 0x80000000'u32) != 0:
        # A complete entry still executes its ordinary header, including any existing native/header accounting.
        offset = target and 0x7fffffff'u32
      else:
        # The original admitted body has every source operation already; neither emission nor pricing is needed.
        let start = f.plan.factAt[int(pc)]
        offset = flatResumePaid(f, target, start)
  if offset == flatStop:
    # Unpaid, missing and invalid entries retain their existing admission, pricing and refusal order.
    offset = flatResolve(f, pc)
  if offset == flatStop:
    f.reason = if f.preparationFailure == FlatError.None: oracle.StepError.InvalidMachine else: oracle.StepError.InvalidPreparedProgram
    return
  while offset != flatStop:
    assert int(offset) < f.handlers.len
    let selected = f.handlers[int(offset)]
    if selected == flatCharge:
      # Preserve temporary barriers: select the first operation only after complete reservation/patching.
      offset = flatReserveHeader(f, offset)
      if offset != flatStop:
        let body = f.handlers[int(offset)]
        offset = body(f, offset)
    else:
      # Specialized charged/native/failure workers retain their existing entry and complete fallback behavior.
      offset = selected(f, offset)
  if f.barrier != flatStop:
    let saved = f.savedHandler
    assert saved != nil
    if saved != nil: f.handlers[int(f.barrier)] = saved
    f.barrier = flatStop
    f.savedHandler = nil
  if f.reason == oracle.StepError.None and f.attemptedExit:
    let sourceFact = f.sites[int(f.stoppedAt)]
    var reservedEnd = f.reservation
    if (reservedEnd and flatReservationHeaderFlag) != 0:
      # Only the final attempted exit needs its exact source end; stream coordinates remain owned and stable.
      let header = reservedEnd and not flatReservationHeaderFlag
      reservedEnd = f.sites[int(header)]+f.arguments[int(header)].y
    if reservedEnd > sourceFact+1:
      f.remaining+=uint64(reservedEnd-sourceFact-1)
  when defined(pvmX86Jit) and not defined(pvmX86WideManualProof):
    # A restored partial barrier or final cached jump can make a pending graph admissible.
    flatX86ColdWideAdmission(f, flatStop)
  flatPromoteNativeLoop(f)

proc runFlatSingle*(f: var FlatFrame) =
  ## Reuse the ordinary charge and opcode workers with one source fact and scalar successor endpoints.
  assert f.plan.singleStep and f.plan.facts.len == 1
  assert f.handlers.len == 0 and f.arguments.len == 0 and f.sites.len == 0
  f.remaining = 1
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  let fact = f.plan.facts[0]
  var cost = 0'u64
  if not f.info.blockCharged:
    # Prepaid stepping does not query an unused price; unpaid entry still charges the genuine containing block.
    let start = containingBlockStart(f.plan.source, CodeAddress(uint64(fact.pc)))
    if start.error != ProgramError.None:
      f.reason = oracle.StepError.InvalidMachine
      return
    let priced = flatPrice(f, start.value, cost)
    if priced != oracle.StepError.None:
      f.reason = priced
      return
  flatEmit(f, flatCharge, FlatArgs(x: cost, y: 1, slots: default(RegisterSlots)), 0)
  let selected = fact.handler
  assert selected != nil
  if selected != nil: flatEmit(f, selected, fact.args, 0)
  flatEmit(f, flatSingleEnd, FlatArgs(x: uint64(fact.next), y: 0, slots: default(RegisterSlots)), 0)
  var offset = 0'u32
  while offset != flatStop:
    assert int(offset) < f.handlers.len
    let handler = f.handlers[int(offset)]
    offset = handler(f, offset)

proc flatCollectResidentPage(f: FlatFrame, page: int, resident: openArray[byte],
    changes: var seq[PageImage]) =
  ## The checked source owner is compared before one changed private page becomes an immutable image.
  let description = f.sourcePages[page]
  let match = matchesMemoryPageBytes(f.sourceMemory, MemoryPageSlot(uint32(page)),
    description, resident)
  assert match.error == MachineError.None
  if match.value: return
  var image = PageImage(index: description.index, access: description.access)
  copyMem(addr image.bytes[0], unsafeAddr resident[0], 4096)
  changes.add(image)

proc flatCollectPage(f: FlatFrame, page: int, changes: var seq[PageImage]) =
  ## Writing original bytes back still publishes no replacement or mutable source alias.
  let description = f.sourcePages[page]
  if description.access != PageAccess.ReadWrite:
    # Preserve the existing checked source-owner validation on an impossible dirty permission.
    var original = PageImage(index: description.index, access: description.access)
    flatCopySourcePage(f.sourceMemory, page, description, original.bytes)
    return
  let address = uint64(uint32(description.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    flatCollectResidentPage(f, page, f.stack.toOpenArray(offset, offset+4095), changes)
    return
  if address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    flatCollectResidentPage(f, page, f.rw.toOpenArray(offset, offset+4095), changes)
    return
  for slot in 0..<f.extra.len:
    let region {.cursor.} = f.extra[slot]
    if region.access == PageAccess.ReadWrite and address >= region.first and
        address-region.first+4096 <= uint64(region.bytes.len):
      let offset = int(address-region.first)
      flatCollectResidentPage(f, page, region.bytes.toOpenArray(offset, offset+4095), changes)
      return
  # Preserve the old checked observer fallback if a future region representation needs it.
  var original = PageImage(index: description.index, access: description.access)
  flatCopySourcePage(f.sourceMemory, page, description, original.bytes)
  var image = original
  for at in 0..<4096: image.bytes[at] = flatByte(f, address+uint64(at))
  if image.bytes != original.bytes: changes.add(image)

proc flatPublishMemory(f: FlatFrame): Memory =
  ## Publish only dirty pages while preserving immutable ownership and sorted replacement order.
  result = f.sourceMemory
  if f.dirtyIndices.len == 0:
    # An untouched epoch has exactly its existing immutable bytes, permissions and local ceiling.
    return
  var changes: seq[PageImage] = @[]
  if f.dirtyIndices.len < f.sourcePages.len div 8:
    # Sparse writes sort only their copied ordinals; publication never mutates the epoch's membership.
    var indices = newSeq[uint32](f.dirtyIndices.len)
    for index in 0..<indices.len: indices[index] = f.dirtyIndices[index]
    indices.sort()
    var start = 0
    for index in indices:
      # A successful store proves membership; binary search skips the untouched portion of a large map.
      var low = start
      var high = f.sourcePages.len
      while low < high:
        let middle = low+(high-low) div 2
        if uint32(f.sourcePages[middle].index) < index: low = middle+1
        else: high = middle
      assert low < f.sourcePages.len and uint32(f.sourcePages[low].index) == index
      flatCollectPage(f, low, changes)
      start = low+1
  else:
    # Dense writes retain the original linear walk instead of sorting nearly the entire mapping.
    for page in 0..<f.sourcePages.len:
      if flatDirty(f, f.sourcePages[page].index):
        flatCollectPage(f, page, changes)
  if changes.len > 0:
    # The checked batch shares untouched owners and clones the root vector exactly once for this observation.
    let updated = withReplacedPages(f.sourceMemory, changes)
    assert updated.error == MachineError.None
    result = updated.value

proc flatMemorySnapshot*(f: FlatFrame): Memory =
  ## A complete independently owned observation; no mutable resident buffer alias escapes.
  flatPublishMemory(f)

proc observeFlatHostMemory*(f: var FlatFrame): Memory =
  ## Bind one genuine stopped host PC to a copied immutable snapshot, retained independently by callers.
  assert f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host
  f.hostSnapshot = flatPublishMemory(f)
  f.hostSnapshotPc = f.info.pc
  f.hostReady = true
  f.hostSnapshot

func flatNodes*(f: FlatFrame): int =
  ## A copied observation reports stream size without exposing mutable cache arrays.
  f.handlers.len

proc checkFlatSource*(f: FlatFrame, expected: openArray[PageImage]) =
  ## An independently captured caller witness checks every immutable baseline byte outside execution.
  assert expected.len == f.sourcePages.len
  for slot in 0..<expected.len:
    # The witness belongs to the caller, never to production frame storage or its resident buffers.
    let description = f.sourcePages[slot]
    assert description.index == expected[slot].index and description.access == expected[slot].access
    let original = pageImage(f.sourceMemory, description.index)
    assert original.error == MachineError.None and original.value.access == expected[
        slot].access and
      original.value.bytes == expected[slot].bytes

proc checkFlatReference*(f: FlatFrame, expected: string, offset: int = 120) =
  ## Compare all current bytes and permissions against the independent complete reference outside clocks.
  assert expected.len == offset+f.sourcePages.len*4096
  for page in 0..<f.sourcePages.len:
    let description = f.sourcePages[page]
    let source = pageImage(f.sourceMemory, description.index)
    assert source.error == MachineError.None
    let image = source.value
    assert image.access == description.access
    for at in 0..<4096:
      # Inaccessible bytes have no resident region and remain solely in their immutable source page.
      let current = if description.access == PageAccess.Inaccessible: image.bytes[at]
        else: flatByte(f, uint64(uint32(description.index))*4096+uint64(at))
      assert current == byte(expected[offset+page*4096+at])

proc prepareFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo): FlatResult[FlatFrame] =
  ## A validated immutable Memory already owns checked page capabilities; retain it instead of recapturing them.
  let count = memoryPageCount(memory)
  if count.error != MachineError.None: return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
  if uint32(count.value) > uint32(plan.limits.pages):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  var layout = memoryLayout(memory)
  if layout.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  var retained = machine.takeValue(layout)
  FlatResult[FlatFrame](status: FlatError.None, completed: buildFlatFrame(plan, retained, info, memory))

proc flatCommitMemoryReplacement(f: var FlatFrame, replacement: var FlatFrame) =
  ## Both callers fully validate a fresh same-plan frame before moving the code-only cache and policies.
  when NativeCheckedReadEnabled:
    # The prior segment always restores its terminal handlers before any host transition.
    assert not f.readProbe.observing
    replacement.readProbe = f.readProbe
  replacement.preparationFailure = f.preparationFailure
  replacement.preparationUsed = f.preparationUsed
  replacement.pricingPlan = f.pricingPlan
  replacement.pricingMemo = f.pricingMemo
  replacement.pricingKind = f.pricingKind
  replacement.handlers = move(f.handlers)
  replacement.arguments = move(f.arguments)
  replacement.sites = move(f.sites)
  replacement.compiledForPc = move(f.compiledForPc)
  replacement.nativeSession = move(f.nativeSession)
  replacement.nativeOriginal = f.nativeOriginal
  replacement.nativeEntry = f.nativeEntry
  replacement.nativeInstalledEpoch = f.nativeInstalledEpoch
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # A same-plan memory replacement preserves code-only capabilities together with their native handlers.
    replacement.armOriginal = move(f.armOriginal)
    replacement.armJit = move(f.armJit)
  when defined(pvmX86Jit):
    replacement.x86Original = move(f.x86Original)
    replacement.x86Jit = move(f.x86Jit)
    replacement.x86WideAdmission = move(f.x86WideAdmission)
  f = move(replacement)

proc replaceFlatMemoryChecked*(f: var FlatFrame, images: openArray[PageImage],
    info: MachineInfo): FlatError =
  ## Trusted observation/reentry replaces memory capabilities wholesale; code cache offsets never retain memory or register owners.
  var prepared = prepareFlatFrame(f.plan, images, info)
  if prepared.error != FlatError.None: return prepared.error
  var replacement = takeValue(prepared)
  flatCommitMemoryReplacement(f, replacement)
  FlatError.None

proc flatReplaceMemoryOwner(f: var FlatFrame, memory: Memory,
    info: MachineInfo): FlatError {.noinline.} =
  ## Keep complete Frame construction off resident host resumes; commit only a fully admitted owner.
  var prepared = prepareFlatMemoryFrame(f.plan, memory, info)
  if prepared.error != FlatError.None: return prepared.error
  var replacement = takeValue(prepared)
  flatCommitMemoryReplacement(f, replacement)
  FlatError.None

proc replaceFlatMemory*(f: var FlatFrame, images: openArray[PageImage], info: MachineInfo) =
  ## Local witness convenience only; the checked boundary preserves a refused frame intact.
  let error = replaceFlatMemoryChecked(f, images, info)
  assert error == FlatError.None

proc resumeFlatHost*(f: var FlatFrame, images: openArray[PageImage], gas: MachineGas,
    registers: RegisterFile) =
  ## The decoder-owned successor, not host-supplied PC/charged metadata, resumes an already paid block.
  assert f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host
  let pc = uint64(f.info.pc)
  assert pc < uint64(f.plan.factAt.len)
  let at = f.plan.factAt[int(pc)]
  assert at >= 0
  var info = f.info
  info.pc = CodeAddress(f.plan.facts[at].next)
  info.gas = gas
  info.registers = registers
  replaceFlatMemory(f, images, info)

proc flatHostPage(f: var FlatFrame, image: PageImage, apply: bool): bool =
  ## Preflight then optionally replace one full private writable page; no byte owner changes or escapes.
  if image.access != PageAccess.ReadWrite: return false
  let address = uint64(uint32(image.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    if apply: copyMem(addr f.stack[offset], unsafeAddr image.bytes[0], 4096)
    return true
  if address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    if apply: copyMem(addr f.rw[offset], unsafeAddr image.bytes[0], 4096)
    return true
  for i in 0..<f.extra.len:
    # Fragmented mappings retain their own immutable access metadata and full-span checks.
    let region {.cursor.} = f.extra[i]
    if region.access == PageAccess.ReadWrite and address >= region.first and
        address-region.first+4096 <= uint64(region.bytes.len):
      let offset = int(address-region.first)
      if apply: copyMem(addr region.bytes[offset], unsafeAddr image.bytes[0], 4096)
      return true
  false

proc resumeFlatHostMemory*(f: var FlatFrame, posterior: Memory, gas: MachineGas,
    registers: RegisterFile): oracle.StepError =
  ## The host supplies immutable posterior memory and scalar CPU changes, never a successor PC/paid flag.
  ## Refused responses leave the complete stopped invocation and observation usable for repair/retry.
  if f.reason != oracle.StepError.None or f.exit != oracle.StepExit.Host or not f.hostReady or
      f.info.pc != f.hostSnapshotPc or not f.info.blockCharged or uint64(f.info.gasDeficit) != 0:
    return oracle.StepError.InvalidHostSuspension
  let pc = uint64(f.info.pc)
  if pc >= uint64(f.plan.factAt.len): return oracle.StepError.InvalidHostSuspension
  let fact = f.plan.factAt[int(pc)]
  if fact < 0: return oracle.StepError.InvalidHostSuspension
  # Reject oversized host mappings before extracting changed pages or allocating replacement storage.
  let count = memoryPageCount(posterior)
  if count.error != MachineError.None or uint32(count.value) > uint32(f.plan.limits.pages):
    return oracle.StepError.InvalidHostResponse
  var delta = changedMemoryPages(f.hostSnapshot, posterior)
  if delta.error == MachineError.InvalidOwner: return oracle.StepError.InvalidHostResponse
  var info = f.info
  info.pc = CodeAddress(f.plan.facts[fact].next)
  info.gas = gas
  info.registers = registers
  var replace = delta.error != MachineError.None
  if not replace:
    let changes = machine.takeValue(delta)
    for i in 0..<changes.len:
      # Complete preflight precedes the first host-byte mutation; unusual capabilities take the slow path.
      if not flatHostPage(f, changes[i], false): replace = true
    if not replace:
      for i in 0..<changes.len:
        let applied = flatHostPage(f, changes[i], true)
        assert applied
      f.sourceMemory = posterior
      flatClearDirty(f)
      f.info = info
      f.reason = oracle.StepError.None
      f.exit = oracle.StepExit.Continued
      f.faultPage = PageAddress(0)
      f.hostCall = oracle.HostCallId(0)
      f.remaining = 0
      f.reservation = 0
      f.stoppedAt = 0
      f.attemptedExit = false
      f.barrier = flatStop
      f.barrierFact = 0
      f.savedHandler = nil
      # The next runFlat entry clears jump offsets before any resumed dispatch.
      f.hostReady = false
      f.hostSnapshot = default(Memory)
      inc f.fastResumes
      f.hostCopiedPages+=uint64(changes.len)
      return oracle.StepError.None
  # Mapping/permission/RO replacement rebuilds all capabilities from a genuine validated snapshot.
  let fast = f.fastResumes
  let fallbacks = f.fallbackResumes
  let pages = f.hostCopiedPages
  if flatReplaceMemoryOwner(f, posterior, info) != FlatError.None:
    return oracle.StepError.InvalidHostResponse
  f.fastResumes = fast
  f.fallbackResumes = fallbacks+1
  f.hostCopiedPages = pages
  oracle.StepError.None

func flatHostStats*(f: FlatFrame): array[3, uint64] =
  ## Copied diagnostic counters: resident resumes, full mapping replacements, copied host pages.
  [f.fastResumes, f.fallbackResumes, f.hostCopiedPages]

type FlatStream* = object
  ## A reusable exclusive cache retains program coordinates/handlers and counters, never CPU or memory.
  handlers: seq[FlatHandler]
  arguments: seq[FlatArgs]
  sites, compiledForPc: seq[uint32]
  sourcePlan: nil FlatPlan # Exact source, emission and default-cycle owner for every build.
  nativeOriginal: nil FlatHandler
  nativeEntry: uint32
  nativeInstalledEpoch: uint64
  pricingKind: byte        # Nondefault sealed headers require fresh emission when leased to another frame.
  failure: FlatError
  preparation: uint64
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    armOriginal: seq[nil FlatHandler]
    armJit: nil ArmJit
  when defined(pvmX86Jit):
    x86Original: seq[nil FlatHandler]
    x86Jit: nil X86Jit
    x86WideAdmission: FlatX86WideAdmission

when defined(pvmArm64Jit) or defined(pvmX86Jit):
  proc `=copy`*(destination: var FlatStream, source: FlatStream) {.error.}
    ## Reject copying an owner that contains exclusive native JIT resources.

  proc `=dup`*(source: FlatStream): FlatStream {.error.}
    ## Reject duplication of an owner that contains exclusive native JIT resources.

proc takeFlatStream*(f: var FlatFrame): FlatStream =
  ## Move the exclusive executable cache back to its prepared owner; generated leaves retain no invocation pointers.
  result = FlatStream(handlers: move(f.handlers), arguments: move(f.arguments), sites: move(f.sites),
    compiledForPc: move(f.compiledForPc), sourcePlan: f.plan, pricingKind: f.pricingKind,
    failure: f.preparationFailure,
    preparation: f.preparationUsed, nativeOriginal: f.nativeOriginal, nativeEntry: f.nativeEntry,
    nativeInstalledEpoch: f.nativeInstalledEpoch)
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # Code and original fallback entries move together with their exact immutable plan and stream coordinates.
    result.armOriginal = move(f.armOriginal)
    result.armJit = move(f.armJit)
  when defined(pvmX86Jit):
    result.x86Original = move(f.x86Original)
    result.x86Jit = move(f.x86Jit)
    result.x86WideAdmission = move(f.x86WideAdmission)

proc restoreFlatStream*(f: var FlatFrame, stream: var FlatStream) =
  ## Lease only exact-source code; CPU, memory, budgets and callbacks remain freshly captured by the frame.
  if stream.sourcePlan != nil and stream.sourcePlan != f.plan:
    # Refuse before consuming another owner's price, executable capability or scalar coordinates.
    f.preparationFailure = FlatError.InvalidProgram
    return
  if f.pricingKind != 0 or stream.pricingKind != 0:
    # A sealed charge/error or native header belongs to its original pricing policy. Reemit under the
    # newly selected policy rather than borrowing an unproven price or retaining another policy owner.
    invalidateNativeStream(f.nativeSession)
    stream = default(FlatStream)
    return
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    f.armOriginal = move(stream.armOriginal)
    f.armJit = move(stream.armJit)
  when defined(pvmX86Jit):
    f.x86Original = move(stream.x86Original)
    f.x86Jit = move(stream.x86Jit)
    f.x86WideAdmission = move(stream.x86WideAdmission)
  stream.sourcePlan = nil
  f.handlers = move(stream.handlers)
  f.arguments = move(stream.arguments)
  f.sites = move(stream.sites)
  f.compiledForPc = move(stream.compiledForPc)
  if stream.failure != FlatError.Uninitialized: f.preparationFailure = stream.failure
  f.preparationUsed = stream.preparation
  f.nativeOriginal = stream.nativeOriginal
  f.nativeEntry = stream.nativeEntry
  f.nativeInstalledEpoch = stream.nativeInstalledEpoch
  flatConsiderNative(f, 0) # Reconsider prior cached code after transient registration capacity becomes available.
  installNative(f)

when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  func streamNativeStatistics*(stream: FlatStream): array[7, uint64] =
    ## Local experiment diagnostics copy counters only; no code pointer, mutable storage or invocation state escapes.
    let jit = stream.armJit
    if jit == nil: return default(array[7, uint64])
    [jit.fragments, jit.calls, jit.operations, jit.codeBytes, jit.compilationNs,
      jit.branchCalls, jit.headerCalls]

when defined(pvmX86Jit):
  func streamNativeStatistics*(stream: FlatStream): array[7, uint64] =
    ## Copy diagnostics only; the code mapping and all mutable owner state remain private.
    let jit = stream.x86Jit
    if jit == nil: return default(array[7, uint64])
    [jit.fragments, jit.calls, jit.operations, jit.codeBytes, jit.compilationNs, jit.branchCalls,
        jit.headerCalls]

  func flatX86Statistics*(frame: FlatFrame): array[5, uint64] =
    ## Focused internal witnesses distinguish native execution from complete checked fallback.
    let jit = frame.x86Jit
    if jit == nil: return default(array[5, uint64])
    [jit.fragments, jit.calls, jit.operations, jit.codeBytes, jit.compilationNs]

  func flatX86ControlStatistics*(frame: FlatFrame): array[2, uint64] =
    ## Copied native branch/header counts prove control executed without exposing the exclusive cache.
    let jit = frame.x86Jit
    if jit == nil: return default(array[2, uint64])
    [jit.branchCalls, jit.headerCalls]

when defined(pvmArm64JitOwnerReceipt):
  func streamArmStatistics*(stream: FlatStream): array[7, uint64] =
    ## Preserve the existing diagnostic API over the same copied cold observation.
    streamNativeStatistics(stream)

when defined(pvmArmMacroReceipt):
  func streamArmMacroStatistics*(stream: FlatStream): array[7, uint64] =
    ## Private copied activity is available after the public invocation returns its cache.
    when defined(pvmArm64Jit):
      let jit {.cursor.} = stream.armJit
      if jit == nil: default(array[7, uint64])
      else: armMacroStatistics(jit)
    else:
      default(array[7, uint64])

  func streamArmMacroResidentActive*(stream: FlatStream): bool =
    ## Private copied kind evidence distinguishes a resident macro on a retained owner.
    when defined(pvmArm64Jit):
      let jit {.cursor.} = stream.armJit
      jit != nil and armMacroResidentActive(jit)
    else:
      false

func streamNodes*(stream: FlatStream): uint64 =
  ## Copied logical occupancy exposes neither mutable arrays nor retained invocation state.
  uint64(stream.handlers.len)

func streamPreparation*(stream: FlatStream): uint64 =
  ## The bounded preparation allowance survives every lease, including local refusal.
  stream.preparation

func planFacts*(plan: FlatPlan): uint64 =
  ## Immutable decoded-fact occupancy belongs to the admitted source owner.
  uint64(plan.facts.len)

func flatScratchSlot(pages: seq[PageDescription], physical: uint32): int =
  ## Same-map validation proves every retained dirty ordinal still belongs to this sorted mapping.
  var low = 0
  var high = pages.len
  while low < high:
    let middle = low+(high-low) div 2
    if uint32(pages[middle].index) < physical: low = middle+1
    else: high = middle
  assert low < pages.len and uint32(pages[low].index) == physical
  low

proc flatRestoreScratchPage(f: var FlatFrame, page: int) =
  ## Complete mapping equality preceded any write; copy one genuine source page into its private allocation.
  let description = f.sourcePages[page]
  if description.access == PageAccess.Inaccessible: return
  let address = uint64(uint32(description.index))*4096
  if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
    let offset = int(address-f.stackBase)
    flatCopySourcePage(f.sourceMemory, page, description, f.stack.toOpenArray(offset, offset+4095))
  elif address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
    let offset = int(address-f.rwBase)
    flatCopySourcePage(f.sourceMemory, page, description, f.rw.toOpenArray(offset, offset+4095))
  elif address >= f.roBase and address-f.roBase+4096 <= uint64(f.ro.len):
    let offset = int(address-f.roBase)
    flatCopySourcePage(f.sourceMemory, page, description, f.ro.toOpenArray(offset, offset+4095))
  else:
    var found = false
    for index in 0..<f.extra.len:
      let region = f.extra[index]
      if address >= region.first and address-region.first+4096 <= uint64(region.bytes.len):
        let offset = int(address-region.first)
        flatCopySourcePage(f.sourceMemory, page, description, region.bytes.toOpenArray(offset, offset+4095))
        found = true
        break
    assert found

proc prepareReusedFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo,
    scratch: var nil FlatMemoryScratch, reused: var bool): FlatResult[FlatFrame] =
  ## Admission and full map/access equality precede reuse; mismatches discard the old idle allocation.
  reused = false
  if scratch == nil: return prepareFlatMemoryFrame(plan, memory, info)
  let count = memoryPageCount(memory)
  if count.error != MachineError.None: return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
  if uint32(count.value) > uint32(plan.limits.pages):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  var held = move(scratch)
  if held == nil: return prepareFlatMemoryFrame(plan, memory, info)
  var delta = changedMemoryPageSlots(held.baseline, memory)
  if delta.error != MachineError.None:
    held = nil
    return prepareFlatMemoryFrame(plan, memory, info)
  var changes = machine.takeValue(delta)
  var frame = flatFrameShell[true](plan, memory, info, held.pages.len)
  frame.sourcePages = move(held.pages)
  frame.roBase = held.roBase
  frame.rwBase = held.rwBase
  frame.stackBase = held.stackBase
  frame.ro = move(held.ro)
  frame.rw = move(held.rw)
  frame.stack = move(held.stack)
  frame.extra = move(held.extra)
  frame.dirtyPages = move(held.dirtyPages)
  frame.dirtyIndices = move(held.dirty)
  for index in 0..<frame.dirtyIndices.len:
    let physical = frame.dirtyIndices[index]
    # Reset guest writes even when the incoming source reuses its exact original owner.
    flatRestoreScratchPage(frame, flatScratchSlot(frame.sourcePages, physical))
  for index in 0..<changes.len:
    let page = int(uint32(changes[index]))
    assert page >= 0 and page < frame.sourcePages.len
    let physical = uint64(uint32(frame.sourcePages[page].index))
    let word = physical shr 6
    # Only a bounded set physical bit proves the first loop already restored incoming bytes.
    # Unknown/short bitmap metadata and clean changed pages retain their complete source copy.
    if word >= uint64(frame.dirtyPages.len) or
        (frame.dirtyPages[int(word)] and (1'u64 shl int(physical and 63))) == 0:
      flatRestoreScratchPage(frame, page)
  flatClearDirty(frame)
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # Every borrowed native descriptor is derived anew from this invocation's moved byte owners.
    flatBuildArmReadContext(frame)
  reused = true
  FlatResult[FlatFrame](status: FlatError.None, completed: move(frame))

proc takeFlatMemoryScratch*(f: var FlatFrame, payloadLimit: uint64): nil FlatMemoryScratch =
  ## Retain only bounded private payload plus one immutable baseline; zero disables retention.
  if payloadLimit == 0: return nil
  var bytes = uint64(f.ro.len)+uint64(f.rw.len)+uint64(f.stack.len)
  for region in f.extra:
    # Disjoint captured regions own exactly their accessible page bytes, including fragmented layouts.
    bytes += uint64(region.bytes.len)
  if bytes == 0: return nil
  let total = bytes+uint64(f.sourcePages.len)*4096
  if total > payloadLimit: return nil
  FlatMemoryScratch(baseline: f.sourceMemory, pages: move(f.sourcePages),
    roBase: f.roBase, rwBase: f.rwBase, stackBase: f.stackBase,
    ro: move(f.ro), rw: move(f.rw), stack: move(f.stack), extra: move(f.extra),
    dirty: move(f.dirtyIndices), dirtyPages: move(f.dirtyPages), payloadBytes: total)

func flatMemoryScratchPayload*(scratch: nil FlatMemoryScratch): uint64 =
  ## Copied logical payload occupancy excludes allocator overhead and remains zero without an idle lease.
  if scratch == nil: 0'u64 else: scratch.payloadBytes

proc selectFlatPrices*(f: var FlatFrame, plan: GasPlan, memo: GasMemo): oracle.StepError =
  ## Complete and lazy policy owners must match the exact immutable program before cache restore or emission.
  if gasPlanInfo(plan).error == GasPlanError.None:
    if not matchesProgram(plan, f.plan.source): return oracle.StepError.InvalidGasPlan
    if f.handlers.len != 0: return oracle.StepError.InvalidPreparedProgram
    f.pricingPlan = plan
    f.pricingKind = 1
  elif gasMemoInfo(memo).error == GasMemoError.None:
    if not matchesProgram(memo, f.plan.source): return oracle.StepError.InvalidGasMemo
    if f.handlers.len != 0: return oracle.StepError.InvalidPreparedProgram
    f.pricingMemo = memo
    f.pricingKind = 2
  oracle.StepError.None
