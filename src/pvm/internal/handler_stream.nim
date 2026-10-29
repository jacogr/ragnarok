# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## GP 0.8.0 checked handler-stream execution with invocation-owned regions and bounded preparation.
## Public immutable snapshot and host adapters live in pvm/step; see spec/pvm-execution.md.
import std/assertions
import ../[program, machine, gas, gas_plan, gas_memo]
import ./execution_types as oracle
import ./register_ops
when defined(pvmArm64Jit) and not defined(pvmX86Jit):
  import ./arm64_jit
when defined(pvmX86Jit):
  import ./x86_jit

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
  FlatFrame* = object ## One exclusively used execution instance; no cache stores an invocation's mutable register/memory state.
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
    sourceImages: seq[PageImage]
    roBase, rwBase, stackBase: uint64
    ro, rw, stack: seq[byte]
    extra: seq[FlatRegion]
    remaining*: uint64
    reservationEnd: uint32
    stoppedAt: uint32
    attemptedExit: bool
    barrier: uint32
    barrierFact: uint32
    savedHandler: nil FlatHandler
    dynamicOffsets: array[256, uint64] # Full positive ordinal tag plus stable offset; no invocation state is retained.
    hostSnapshot: Memory
    hostChanges: seq[PageImage]
    hostReady: bool
    hostSnapshotPc: CodeAddress
    fastResumes, fallbackResumes, hostCopiedPages: uint64
    dirtyPages: seq[uint64] # One bounded 128 KiB bitmap covers all 32-bit guest pages.
    preparationFailure: FlatError # Rare admission state leaves all existing hot-frame coordinates unchanged.
    preparationUsed: uint64 # Cold source-span reservations persist with the emitted cache across resets/reentry.
    pricingPlan: GasPlan    # Optional source-bound immutable prices, selected only during cold emission.
    pricingMemo: GasMemo    # Optional caller-owned bounded price memo, never CPU or paid gas.
    when defined(pvmArm64Jit) and not defined(pvmX86Jit):
      armOriginal: seq[nil FlatHandler] # Original entries restore exact checked fallback on partial source reservations.
      armJit: nil ArmJit # Exclusively leased code cache retains no invocation CPU, memory or callback addresses.
    when defined(pvmX86Jit):
      x86Original: seq[nil FlatHandler] # Exact checked entries survive every partial reservation and native refusal.
      x86Jit: nil X86Jit    # Exclusive code-only owner; never contains an invocation address.
      x86PreviousHeader, x86PreviousNext: uint32 # Observed invocation-local edges discover only closed pure loops.
      x86PreviousValid: bool
    pricingKind: byte       # Zero dynamic, one complete plan, two lazy memo; no per-op pricing switch.
    when defined(pvmArm64Jit) and not defined(pvmX86Jit):
      armPreviousHeader, armPreviousNext: uint32 # Invocation-local observed pure-block edges, never retained in source caches.
      armPreviousValid: bool
      armMemory: array[3, array[3, uint64]] # Frame-owned base/extent/borrowed pointer descriptors; never retained by FlatStream.




type FlatPublication = object
  ## One owned immutable observation and the copied writable pages that differ from its source base.
  memory: Memory
  changed: seq[PageImage]

when defined(pvmArm64Jit) or defined(pvmX86Jit):
  proc `=copy`*(destination: var FlatFrame, source: FlatFrame) {.error.}
  proc `=dup`*(source: FlatFrame): FlatFrame {.error.}

const flatStop = high(uint32)

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
  let reserved = min(f.remaining, uint64(a.y))
  f.remaining-=reserved
  f.reservationEnd = f.sites[int(off)]+uint32(reserved)
  if reserved < uint64(a.y):
    f.barrierFact = f.reservationEnd
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

proc flatCharge(f: var FlatFrame, off: uint32): uint32 =
  ## Ordinary headers retain their original indirect handoff after the shared complete reservation checks.
  flatReserve(f, off)
  # A successful entry consumes the next already sealed handler immediately; at most the existing
  # disjoint operation prefix adds a third call. Control transfers return offsets, never recurse.
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

proc flatChargeFailure[Error: static[oracle.StepError]](f: var FlatFrame, off: uint32): uint32 =
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

proc flatMarkStore[W: static[int]](f: var FlatFrame, address: uint64) {.inline.} =
  ## Mark only after complete store preflight; no allocation or guest-visible state changes occur here.
  assert address <= uint64(high(uint32))-uint64(W-1)
  let first = int(address shr 12)
  let word = first shr 6
  assert word < f.dirtyPages.len
  let mask = 1'u64 shl (first and 63)
  let before = f.dirtyPages[word]
  if (before and mask) == 0:
    # A dirty epoch needs one bit transition per page, even when the guest rewrites it repeatedly.
    f.dirtyPages[word] = before or mask
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
        f.dirtyPages[lastWord] = lastBefore or lastMask

proc flatClearDirty(f: var FlatFrame) =
  ## A successful host checkpoint or input reset makes private bytes equal their immutable base again.
  for word in 0..<f.dirtyPages.len: f.dirtyPages[word] = 0

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
  ## Rare complete immutable store preflight is discarded; private bytes mutate atomically only after its exact typed success.
  let checked = store(f.sourceMemory, MemoryAddress(address), AccessWidth(byte(W)), RegisterValue(value))
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

proc flatLoad[W: static[int]](f: var FlatFrame, off: uint32, address: uint64,
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
  flatLoadSlow[W](f, off, address, value)

proc flatStore[W: static[int]](f: var FlatFrame, off: uint32, address,
    value: uint64): bool {.alwaysInline.} =
  ## Only captured writable/stack regions can satisfy a fast store; RO and fragmented boundaries retain full preflight.
  if address >= 65536'u64 and address <= uint64(high(uint32))-uint64(W):
    if address >= f.stackBase:
      let at = int(address-f.stackBase)
      if f.stack.len >= W and at <= f.stack.len-W:
        flatMarkStore[W](f, address)
        flatWrite[W](f.stack, at, value)
        return true
    elif address >= f.rwBase:
      let at = int(address-f.rwBase)
      if f.rw.len >= W and at <= f.rw.len-W:
        flatMarkStore[W](f, address)
        flatWrite[W](f.rw, at, value)
        return true
  flatStoreSlow[W](f, off, address, value)

proc flatMemory[Width: static[int]; Loading, Signed, Indirect, ImmediateStore: static[bool]](
    f: var FlatFrame, off: uint32): uint32 =
  ## Adapt our complete selected-width memory worker to the checked private region backend.
  let a = f.arguments[int(off)]
  var base = 0'u64
  when Indirect:
    when Loading or not ImmediateStore: base = uint64(f.info.registers[a.slots.bIndex])
    else: base = uint64(f.info.registers[a.slots.aIndex])
  let address = (base+a.x) and 0xffffffff'u64
  when Loading:
    var value = 0'u64
    if not flatLoad[Width](f, off, address, value): return flatStop
    when Signed:
      let bits = Width*8
      if (value and (1'u64 shl (bits-1))) != 0: value = value or (high(uint64) shl bits)
    f.info.registers[a.slots.aIndex] = RegisterValue(value)
  else:
    let value = when ImmediateStore: flatSext32(a.y) else: uint64(f.info.registers[a.slots.aIndex])
    if not flatStore[Width](f, off, address, value): return flatStop
  off+1

proc flatMemoryPair[Width: static[int]; Loading, Signed, Indirect, ImmediateStore: static[bool]](
    f: var FlatFrame, off: uint32): uint32 =
  ## Adapt our complete selected-width memory worker to the checked private region backend.
  let a = f.arguments[int(off)]
  var base = 0'u64
  when Indirect:
    when Loading or not ImmediateStore: base = uint64(f.info.registers[a.slots.bIndex])
    else: base = uint64(f.info.registers[a.slots.aIndex])
  let address = (base+a.x) and 0xffffffff'u64
  when Loading:
    var value = 0'u64
    if not flatLoad[Width](f, off, address, value): return flatStop
    when Signed:
      let bits = Width*8
      if (value and (1'u64 shl (bits-1))) != 0: value = value or (high(uint64) shl bits)
    f.info.registers[a.slots.aIndex] = RegisterValue(value)
  else:
    let value = when ImmediateStore: flatSext32(a.y) else: uint64(f.info.registers[a.slots.aIndex])
    if not flatStore[Width](f, off, address, value): return flatStop
  let next = off+1
  let selected = f.handlers[int(next)]
  selected(f, next)

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
  of 30: flatMemory[1, false, false, false, true]
  of 31: flatMemory[2, false, false, false, true]
  of 32: flatMemory[4, false, false, false, true]
  of 33: flatMemory[8, false, false, false, true]
  of 40: (if valid: flatJump[40] else: flatBadControl[40])
  of 50: flatDynamic[50, false]
  of 51: flatRegister[51]
  of 52: flatMemory[1, true, false, false, false]
  of 53: flatMemory[1, true, true, false, false]
  of 54: flatMemory[2, true, false, false, false]
  of 55: flatMemory[2, true, true, false, false]
  of 56: flatMemory[4, true, false, false, false]
  of 57: flatMemory[4, true, true, false, false]
  of 58: flatMemory[8, true, false, false, false]
  of 59: flatMemory[1, false, false, false, false]
  of 60: flatMemory[2, false, false, false, false]
  of 61: flatMemory[4, false, false, false, false]
  of 62: flatMemory[8, false, false, false, false]
  of 70: flatMemory[1, false, false, true, true]
  of 71: flatMemory[2, false, false, true, true]
  of 72: flatMemory[4, false, false, true, true]
  of 73: flatMemory[8, false, false, true, true]
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
  of 120: flatMemory[1, false, false, true, false]
  of 121: flatMemory[2, false, false, true, false]
  of 122: flatMemory[4, false, false, true, false]
  of 123: flatMemory[8, false, false, true, false]
  of 124: flatMemory[1, true, false, true, false]
  of 125: flatMemory[1, true, true, true, false]
  of 126: flatMemory[2, true, false, true, false]
  of 127: flatMemory[2, true, true, true, false]
  of 128: flatMemory[4, true, false, true, false]
  of 129: flatMemory[4, true, true, true, false]
  of 130: flatMemory[8, true, false, true, false]
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
  of 30: flatMemoryPair[1, false, false, false, true]
  of 31: flatMemoryPair[2, false, false, false, true]
  of 32: flatMemoryPair[4, false, false, false, true]
  of 33: flatMemoryPair[8, false, false, false, true]
  of 52: flatMemoryPair[1, true, false, false, false]
  of 53: flatMemoryPair[1, true, true, false, false]
  of 54: flatMemoryPair[2, true, false, false, false]
  of 55: flatMemoryPair[2, true, true, false, false]
  of 56: flatMemoryPair[4, true, false, false, false]
  of 57: flatMemoryPair[4, true, true, false, false]
  of 58: flatMemoryPair[8, true, false, false, false]
  of 59: flatMemoryPair[1, false, false, false, false]
  of 60: flatMemoryPair[2, false, false, false, false]
  of 61: flatMemoryPair[4, false, false, false, false]
  of 62: flatMemoryPair[8, false, false, false, false]
  of 70: flatMemoryPair[1, false, false, true, true]
  of 71: flatMemoryPair[2, false, false, true, true]
  of 72: flatMemoryPair[4, false, false, true, true]
  of 73: flatMemoryPair[8, false, false, true, true]
  of 120: flatMemoryPair[1, false, false, true, false]
  of 121: flatMemoryPair[2, false, false, true, false]
  of 122: flatMemoryPair[4, false, false, true, false]
  of 123: flatMemoryPair[8, false, false, true, false]
  of 124: flatMemoryPair[1, true, false, true, false]
  of 125: flatMemoryPair[1, true, true, true, false]
  of 126: flatMemoryPair[2, true, false, true, false]
  of 127: flatMemoryPair[2, true, true, true, false]
  of 128: flatMemoryPair[4, true, false, true, false]
  of 129: flatMemoryPair[4, true, true, true, false]
  of 130: flatMemoryPair[8, true, false, true, false]
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
  while pc < extent.value:
    if uint64(owner.facts.len) >= uint64(limits.facts):
      return FlatResult[FlatPlan](status: FlatError.FactLimitExceeded)
    let decoded = instruction(source, CodeAddress(pc))
    if decoded.error != ProgramError.None: return FlatResult[FlatPlan](
        status: FlatError.InvalidProgram)
    let item = decoded.value
    let begins = basicBlockStart(source, item.address)
    if begins.error != ProgramError.None: return FlatResult[FlatPlan](
        status: FlatError.InvalidProgram)
    if begins.value:
      priceIndex = uint32(owner.pricePcs.len)
      owner.pricePcs.add(item.address)
    let fact = flatFact(decoded, priceIndex)
    owner.factAt[int(pc)] = owner.facts.len
    owner.facts.add(fact)
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
  var pairedPrevious = false
  while index < f.plan.facts.len:
    let fact = f.plan.facts[index]
    let coordinate = uint32(f.handlers.len)
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
      # Pairs never overlap: the second node stays the original handler, so no recursive handler chain can form.
      if not pairedPrevious and fact.fallthrough:
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
          pairedPrevious = true
        else: pairedPrevious = false
      else: pairedPrevious = false
      if selected != nil: flatEmit(f, selected, fact.args, uint32(index))
    if fact.ending: break
    inc index
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    flatArmPrepare(f, origin)
  when defined(pvmX86Jit):
    flatX86Prepare(f, origin)
  origin

proc resetFlatFrame*(f: var FlatFrame, info: MachineInfo) =
  ## Restore input outside the execution clock, preserving the explicit reset boundary; cached code/links alone persist.
  flatClearDirty(f)
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.hostChanges = @[]
  f.info = info
  f.reason = oracle.StepError.None
  f.exit = oracle.StepExit.Continued
  f.faultPage = PageAddress(0)
  f.hostCall = oracle.HostCallId(0)
  for page in 0..<f.sourceImages.len:
    let image = f.sourceImages[page]
    if image.access == PageAccess.Inaccessible: continue
    let address = uint64(uint32(image.index))*4096
    if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
      let offset = int(address-f.stackBase)
      copyMem(addr f.stack[offset], unsafeAddr image.bytes[0], 4096)
    elif address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
      let offset = int(address-f.rwBase)
      copyMem(addr f.rw[offset], unsafeAddr image.bytes[0], 4096)
    elif address >= f.roBase and address-f.roBase+4096 <= uint64(f.ro.len):
      let offset = int(address-f.roBase)
      copyMem(addr f.ro[offset], unsafeAddr image.bytes[0], 4096)
    else:
      var found = false
      for i in 0..<f.extra.len:
        let region {.cursor.} = f.extra[i]
        if address >= region.first and address-region.first+4096 <= uint64(region.bytes.len):
          let offset = int(address-region.first)
          copyMem(addr region.bytes[offset], unsafeAddr image.bytes[0], 4096)
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

proc buildFlatFrame(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo,
    memory: Memory): FlatFrame =
  ## Own checked private region copies without borrowing caller byte storage; arbitrary fragmented layouts retain a genuine slow preflight owner.
  assert plan != nil
  # Admission already bounds the page count; also prove the exact owned snapshot allocation fits host indexing.
  assert images.len <= high(int) div sizeof(PageImage)
  result = FlatFrame(plan: plan, preparationFailure: FlatError.None, preparationUsed: 0,
      hostSnapshot: default(Memory), hostChanges: @[], hostReady: false,
    hostSnapshotPc: CodeAddress(0), fastResumes: 0, fallbackResumes: 0, hostCopiedPages: 0,
    # No store can succeed in an empty genuine map; a later host remap rebuilds this frame and its bitmap.
    dirtyPages: (if images.len == 0: @[] else: newSeq[uint64](16384)),
        info: info, reason: oracle.StepError.None,
    exit: oracle.StepExit.Continued,
    faultPage: PageAddress(0), hostCall: oracle.HostCallId(0), handlers: @[], arguments: @[],
        sites: @[],
    compiledForPc: @[], sourceMemory: memory, sourceImages: newSeqOfCap[PageImage](
        images.len),
    roBase: 0, rwBase: uint64(high(uint32)), stackBase: uint64(high(uint32)), ro: @[], rw: @[],
        stack: @[], extra: @[],
    remaining: 0, reservationEnd: 0, stoppedAt: 0, attemptedExit: false, barrier: flatStop,
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

  var regions: seq[FlatRegion] = @[]
  var first = 0
  while first < images.len:
    let image = images[first]
    if image.access == PageAccess.Inaccessible:
      # Inaccessible pages retain their original snapshot metadata without authorizing a private byte region.
      result.sourceImages.add(image)
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
      result.sourceImages.add(images[page])
      let offset = (page-first)*4096
      assert offset >= 0 and offset <= region.bytes.len-4096
      copyMem(addr region.bytes[offset], unsafeAddr images[page].bytes[0], 4096)
    regions.add(region)
    first = after
  # A refused growth must never publish a truncated source snapshot, including for a valid empty mapping.
  assert result.sourceImages.len == images.len
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
    result.armMemory[0] = flatArmReadRegion(result.stackBase, result.stack)
    result.armMemory[1] = flatArmReadRegion(result.rwBase, result.rw)
    result.armMemory[2] = flatArmReadRegion(result.roBase, result.ro)

proc prepareFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatResult[FlatFrame] =
  ## Validate complete page admission before private region copies; a refusal contains no partial frame.
  if uint64(images.len) > uint64(uint32(plan.limits.pages)):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  let memory = captureMemory(images, plan.limits.pages)
  if memory.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  FlatResult[FlatFrame](status: FlatError.None, completed: buildFlatFrame(plan, images, info, memory.value))

proc newFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatFrame =
  ## Local witness convenience only; application admission uses prepareFlatFrame and checks its typed result.
  var prepared = prepareFlatFrame(plan, images, info)
  assert prepared.error == FlatError.None
  takeValue(prepared)

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
    f.reservationEnd = f.sites[int(offset)]+args.y
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
      # The last completed block's endpoint stays exact even when the next header returns on a quota/gas guard.
      assert state[4] < uint64(f.arguments.len)
      let last = uint32(state[4])
      f.reservationEnd = f.sites[int(last)]+f.arguments[int(last)].y
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
    # Retain the exact endpoint even for complete native blocks; observable exit/refund behavior has no new dependency.
    f.reservationEnd = f.sites[int(offset)]+args.y
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

  proc flatArmMemory(f: var FlatFrame, offset: uint32): uint32 =
    ## A partial reservation uses the original source nodes; native guard refusal replays the untouched checked memory operation.
    if f.barrier == flatStop:
      block:
        # End all descriptor/register borrows before a guard failure invokes the full mutable checked worker.
        let jit {.cursor.} = f.armJit
        assert jit != nil
        if jit != nil:
          let destination = callArmMemory(jit, offset, f.info.registers, f.armMemory)
          if destination != flatStop: return destination
    let original = f.armOriginal[int(offset)]
    assert original != nil
    if original != nil: return original(f, offset)
    flatLocal(f, offset, oracle.StepError.InvalidPreparedProgram)

  proc flatArmCompileReadSpan(f: var FlatFrame, offset: uint32): uint32 =
    ## Combine only multiple unsigned word reads and pure arithmetic within one already-reserved source block.
    let jit = f.armJit
    assert jit != nil
    if jit == nil: return offset
    var ending = offset
    var count = 0'u32
    var reads = 0'u32
    var written = 0'u32
    var window = true
    let base = f.plan.facts[int(f.sites[int(offset)])].args.slots.bIndex
    var first = high(uint32)
    var last = 0'u32
    while int(ending) < f.sites.len and count < 64:
      # Headers, stores, narrower reads, branches, hosts and every observable exit end the speculative prefix.
      if int(ending)+1 < f.sites.len and f.sites[int(ending)] == f.sites[int(ending)+1]: break
      let fact = f.plan.facts[int(f.sites[int(ending)])]
      if fact.ending or not fact.fallthrough: break
      if fact.opcode == 130:
        let displacement = uint32(fact.args.x and 0xffffffff'u64)
        if fact.args.slots.bIndex != base or (written and (1'u32 shl int(base))) != 0:
          window = false # Derived or overwritten address bases retain the accepted individual guards.
        if displacement < first: first = displacement
        if displacement > last: last = displacement
        written = written or (1'u32 shl int(fact.args.slots.aIndex))
        inc reads
      elif supportedArmOpcode(fact.opcode):
        written = written or (1'u32 shl int(fact.args.slots.destinationIndex))
      else:
        break # Unsupported semantics remain their original checked source node.
      inc ending
      inc count
    if reads < 2 or count < 4: return offset
    if last-first > 4088: window = false
    var native = default(ArmReadSpan)
    if window:
      # Relative scaled loads need equal low displacement bits; the initial effective address may still be unaligned.
      for current in offset..<ending:
        let fact = f.plan.facts[int(f.sites[int(current)])]
        if fact.opcode == 130 and (uint32(fact.args.x and 0xffffffff'u64)-first) mod 8 != 0:
          window = false
    if window: beginArmReadWindow(native, base, first, last)
    for current in offset..<ending:
      # Only a proved stable base uses the shared window; all other mixed spans preserve their original lowering.
      let fact = f.plan.facts[int(f.sites[int(current)])]
      if fact.opcode == 130:
        let displacement = uint32(fact.args.x and 0xffffffff'u64)
        if window: emitArmWindowRead(native, fact.args.slots.aIndex, displacement-first)
        else: emitArmRead(native, fact.args.slots, displacement)
      else:
        emitArmReadArithmetic(native, fact.opcode, fact.args.slots, fact.args.x)
    var words = armReadInstructions(native, ending)
    if words.len >= 1024: return offset # Oversized spans retain the accepted first-read leaf, without poisoning its admission.
    if not publishArmEntry(jit, offset, ending, count, words): return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmMemory
    ending

  proc flatArmCompileMemory(f: var FlatFrame, offset: uint32): uint32 =
    ## Admit only a first unsigned indirect word load with at least three pure suffix operations, preserving every source coordinate.
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
    if int(ending) < f.sites.len and f.plan.facts[int(f.sites[int(ending)])].opcode == 130:
      # Only an encountered second word read can justify the transactional span builder.
      let combined = flatArmCompileReadSpan(f, offset)
      if combined != offset: return combined
    if count < 4:
      refuseArmEntry(jit, offset)
      return offset
    let args = f.arguments[int(offset)]
    var words = armMemoryInstructions(native, args.slots, uint32(args.x and 0xffffffff'u64), ending)
    if not publishArmEntry(jit, offset, ending, count, words): return offset
    if f.armOriginal.len < f.handlers.len: f.armOriginal.setLen(f.handlers.len)
    f.armOriginal[int(offset)] = f.handlers[int(offset)]
    f.handlers[int(offset)] = flatArmMemory
    ending

  proc flatArmCompile(f: var FlatFrame, offset: uint32): uint32 =
    ## Compilation happens only during lazy stream emission, never as a universal dispatch probe.
    if f.armJit == nil: f.armJit = newArmJit()
    let jit = f.armJit
    if jit == nil: return offset
    let entry = armEntry(jit, offset, uint32(f.handlers.len))
    if entry != 0: return offset
    if int(offset)+1 < f.sites.len and f.sites[int(offset)] == f.sites[int(offset)+1]: return offset
    if f.plan.facts[int(f.sites[int(offset)])].opcode == 130: return flatArmCompileMemory(f, offset)
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

proc runFlat*(f: var FlatFrame, limit: uint64) =
  ## The hot loop is the offset-returning dispatch; budgets are reserved only at synthetic block entries.
  f.hostReady = false
  f.hostSnapshot = default(Memory)
  f.hostChanges = @[]
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
  f.dynamicOffsets = default(array[256, uint64]) # Invocation reset remains inside execution timing.
  var offset = flatResolve(f, uint32(uint64(f.info.pc) and 0xffffffff'u64))
  if offset == flatStop:
    f.reason = if f.preparationFailure == FlatError.None: oracle.StepError.InvalidMachine else: oracle.StepError.InvalidPreparedProgram
    return
  while offset != flatStop:
    assert int(offset) < f.handlers.len
    let selected = f.handlers[int(offset)]
    offset = selected(f, offset)
  if f.barrier != flatStop:
    let saved = f.savedHandler
    assert saved != nil
    if saved != nil: f.handlers[int(f.barrier)] = saved
    f.barrier = flatStop
    f.savedHandler = nil
  if f.reason == oracle.StepError.None and f.attemptedExit:
    let sourceFact = f.sites[int(f.stoppedAt)]
    if f.reservationEnd > sourceFact+1:
      f.remaining+=uint64(f.reservationEnd-sourceFact-1)

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

proc flatPublishMemory(f: FlatFrame, keepChanges: bool): FlatPublication =
  ## Reuse genuine immutable source pages; changed writable pages publish copied bytes, never private buffer aliases.
  result = FlatPublication(memory: f.sourceMemory, changed: @[])
  if f.sourceImages.len == 0:
    # A genuine frame always owns a valid source root; keep an empty posterior's exact local ceiling.
    return
  var changes: seq[PageImage] = @[]
  for page in 0..<f.sourceImages.len:
    # Read only metadata before the filter, avoiding even a temporary page copy for clean pages.
    if not flatDirty(f, f.sourceImages[page].index): continue
    let original = f.sourceImages[page]
    if original.access == PageAccess.ReadWrite:
      # Guest writes cannot change RO/inaccessible pages; only writable pages need current-byte comparison.
      var image = original
      let address = uint64(uint32(image.index))*4096
      var copied = false
      if address >= f.stackBase and address-f.stackBase+4096 <= uint64(f.stack.len):
        # The entire page belongs to this retained private region; stack temporary and heap bytes are disjoint.
        let offset = int(address-f.stackBase)
        copyMem(addr image.bytes[0], unsafeAddr f.stack[offset], 4096)
        copied = true
      elif address >= f.rwBase and address-f.rwBase+4096 <= uint64(f.rw.len):
        let offset = int(address-f.rwBase)
        copyMem(addr image.bytes[0], unsafeAddr f.rw[offset], 4096)
        copied = true
      else:
        # Fragmented captured writable regions retain the same full-span proof before a copy.
        for slot in 0..<f.extra.len:
          let region {.cursor.} = f.extra[slot]
          if region.access == PageAccess.ReadWrite and address >= region.first and
              address-region.first+4096 <= uint64(region.bytes.len):
            let offset = int(address-region.first)
            copyMem(addr image.bytes[0], unsafeAddr region.bytes[offset], 4096)
            copied = true
            break
      if not copied:
        # Preserve the original checked observer fallback if a future region representation needs it.
        for at in 0..<4096: image.bytes[at] = flatByte(f, address+uint64(at))
      if image.bytes != original.bytes:
        # Collect only changed writable pages in the already sorted source order; all costs stay inside publication.
        changes.add(image)
  if changes.len > 0:
    # The checked batch shares untouched owners and clones the root vector exactly once for this observation.
    let updated = withReplacedPages(f.sourceMemory, changes)
    assert updated.error == MachineError.None
    result.memory = updated.value
    if keepChanges: result.changed = move(changes)

proc flatMemorySnapshot*(f: FlatFrame): Memory =
  ## A complete independently owned observation; no mutable resident buffer alias escapes.
  flatPublishMemory(f, false).memory

proc observeFlatHostMemory*(f: var FlatFrame): Memory =
  ## Bind one genuine stopped host PC to a copied immutable snapshot, retained independently by callers.
  assert f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host
  var published = flatPublishMemory(f, true)
  f.hostSnapshot = published.memory
  f.hostChanges = move(published.changed)
  f.hostSnapshotPc = f.info.pc
  f.hostReady = true
  f.hostSnapshot

func flatNodes*(f: FlatFrame): int =
  ## A copied observation reports stream size without exposing mutable cache arrays.
  f.handlers.len

proc checkFlatSource*(f: FlatFrame) =
  ## Every original mapped byte and permission remains immutable despite private execution and reset.
  for i in 0..<f.sourceImages.len:
    let image = pageImage(f.sourceMemory, f.sourceImages[i].index)
    assert image.error == MachineError.None
    let original = image.value
    assert original.access == f.sourceImages[i].access and original.bytes == f.sourceImages[i].bytes

proc checkFlatReference*(f: FlatFrame, expected: string, offset: int = 120) =
  ## Compare private current bytes and unchanged source images outside execution, without publishing another memory representation.
  assert expected.len == offset+f.sourceImages.len*4096
  for page in 0..<f.sourceImages.len:
    let original = f.sourceImages[page]
    let source = pageImage(f.sourceMemory, original.index)
    assert source.error == MachineError.None
    let image = source.value
    assert image.access == original.access and image.bytes == original.bytes
    for at in 0..<4096:
      let current = if original.access == PageAccess.Inaccessible: original.bytes[at]
        else: flatByte(f, uint64(uint32(original.index))*4096+uint64(at))
      assert current == byte(expected[offset+page*4096+at])

proc replaceFlatMemoryChecked*(f: var FlatFrame, images: openArray[PageImage],
    info: MachineInfo): FlatError =
  ## Trusted observation/reentry replaces memory capabilities wholesale; code cache offsets never retain memory or register owners.
  var prepared = prepareFlatFrame(f.plan, images, info)
  if prepared.error != FlatError.None: return prepared.error
  var replacement = takeValue(prepared)
  replacement.preparationFailure = f.preparationFailure
  replacement.preparationUsed = f.preparationUsed
  replacement.pricingPlan = f.pricingPlan
  replacement.pricingMemo = f.pricingMemo
  replacement.pricingKind = f.pricingKind
  replacement.handlers = move(f.handlers)
  replacement.arguments = move(f.arguments)
  replacement.sites = move(f.sites)
  replacement.compiledForPc = move(f.compiledForPc)
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # A same-plan memory replacement preserves code-only capabilities together with their native handlers.
    replacement.armOriginal = move(f.armOriginal)
    replacement.armJit = move(f.armJit)
  when defined(pvmX86Jit):
    replacement.x86Original = move(f.x86Original)
    replacement.x86Jit = move(f.x86Jit)
  f = move(replacement)

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

proc flatRefreshImages(f: var FlatFrame, changes: openArray[PageImage]) =
  ## Advance only copied changed checkpoint pages after a successful response, preserving reset semantics.
  var slot = 0
  for i in 0..<changes.len:
    # Sorted checkpoint changes may skip thousands of clean pages; narrow only the remaining source suffix.
    var low = slot
    var high = f.sourceImages.len
    while low < high:
      let middle = low+(high-low) div 2
      if uint32(f.sourceImages[middle].index) < uint32(changes[i].index): low = middle+1
      else: high = middle
    slot = low
    assert slot < f.sourceImages.len and f.sourceImages[slot].index == changes[i].index
    f.sourceImages[slot] = changes[i]

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
  # Reject oversized host mappings before extracting a copied delta or any complete page array.
  let count = memoryPageCount(posterior)
  if count.error != MachineError.None or uint32(count.value) > uint32(f.plan.limits.pages):
    return oracle.StepError.InvalidHostResponse
  let delta = changedMemoryPages(f.hostSnapshot, posterior)
  if delta.error == MachineError.InvalidOwner: return oracle.StepError.InvalidHostResponse
  var info = f.info
  info.pc = CodeAddress(f.plan.facts[fact].next)
  info.gas = gas
  info.registers = registers
  var replace = delta.error != MachineError.None
  if not replace:
    let changes = delta.value
    for i in 0..<changes.len:
      # Complete preflight precedes the first host-byte mutation; unusual capabilities take the slow path.
      if not flatHostPage(f, changes[i], false): replace = true
    if not replace:
      for i in 0..<changes.len:
        let applied = flatHostPage(f, changes[i], true)
        assert applied
      var guestChanges = move(f.hostChanges)
      flatRefreshImages(f, guestChanges)
      flatRefreshImages(f, changes)
      f.sourceMemory = posterior
      flatClearDirty(f)
      f.info = info
      f.reason = oracle.StepError.None
      f.exit = oracle.StepExit.Continued
      f.faultPage = PageAddress(0)
      f.hostCall = oracle.HostCallId(0)
      f.remaining = 0
      f.reservationEnd = 0
      f.stoppedAt = 0
      f.attemptedExit = false
      f.barrier = flatStop
      f.barrierFact = 0
      f.savedHandler = nil
      f.dynamicOffsets = default(array[256, uint64])
      f.hostReady = false
      f.hostSnapshot = default(Memory)
      inc f.fastResumes
      f.hostCopiedPages+=uint64(changes.len)
      return oracle.StepError.None
  # Mapping/permission/RO replacement rebuilds all capabilities from a genuine validated snapshot.
  let complete = memoryImages(posterior)
  if complete.error != MachineError.None: return oracle.StepError.InvalidHostResponse
  let fast = f.fastResumes
  let fallbacks = f.fallbackResumes
  let pages = f.hostCopiedPages
  if replaceFlatMemoryChecked(f, complete.value, info) != FlatError.None:
    return oracle.StepError.InvalidHostResponse
  f.sourceMemory = posterior # Preserve the host snapshot's local mapping policy as well as bytes/permissions.
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
  failure: FlatError
  preparation: uint64
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    armPlan: nil FlatPlan # Exact immutable source/emission owner; offsets alone never authorize code reuse.
    armOriginal: seq[nil FlatHandler]
    armJit: nil ArmJit
  when defined(pvmX86Jit):
    x86Plan: nil FlatPlan # Code offsets are capabilities only for this exact immutable source owner.
    x86Original: seq[nil FlatHandler]
    x86Jit: nil X86Jit

when defined(pvmArm64Jit) or defined(pvmX86Jit):
  proc `=copy`*(destination: var FlatStream, source: FlatStream) {.error.}
  proc `=dup`*(source: FlatStream): FlatStream {.error.}

proc takeFlatStream*(f: var FlatFrame): FlatStream =
  ## Move the exclusive executable cache back to its prepared owner; generated leaves retain no invocation pointers.
  result = FlatStream(handlers: move(f.handlers), arguments: move(f.arguments), sites: move(f.sites),
    compiledForPc: move(f.compiledForPc), failure: f.preparationFailure,
    preparation: f.preparationUsed)
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    # Code and original fallback entries move together with their exact immutable plan and stream coordinates.
    result.armPlan = f.plan
    result.armOriginal = move(f.armOriginal)
    result.armJit = move(f.armJit)
  when defined(pvmX86Jit):
    result.x86Plan = f.plan
    result.x86Original = move(f.x86Original)
    result.x86Jit = move(f.x86Jit)

proc restoreFlatStream*(f: var FlatFrame, stream: var FlatStream) =
  ## Lease only exact-source code; CPU, memory, budgets and callbacks remain freshly captured by the frame.
  when defined(pvmArm64Jit) and not defined(pvmX86Jit):
    if stream.armPlan != nil and stream.armPlan != f.plan:
      # Refuse before consuming another owner's executable capability or changing its scalar coordinates.
      f.preparationFailure = FlatError.InvalidProgram
      return
    f.armOriginal = move(stream.armOriginal)
    f.armJit = move(stream.armJit)
    stream.armPlan = nil
  when defined(pvmX86Jit):
    if stream.x86Plan != nil and stream.x86Plan != f.plan:
      f.preparationFailure = FlatError.InvalidProgram
      return # Refuse before consuming either source owner's exclusive cache.
    f.x86Original = move(stream.x86Original)
    f.x86Jit = move(stream.x86Jit)
    stream.x86Plan = nil
  f.handlers = move(stream.handlers)
  f.arguments = move(stream.arguments)
  f.sites = move(stream.sites)
  f.compiledForPc = move(stream.compiledForPc)
  if stream.failure != FlatError.Uninitialized: f.preparationFailure = stream.failure
  f.preparationUsed = stream.preparation

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

func streamNodes*(stream: FlatStream): uint64 =
  ## Copied logical occupancy exposes neither mutable arrays nor retained invocation state.
  uint64(stream.handlers.len)

func streamPreparation*(stream: FlatStream): uint64 =
  ## The bounded preparation allowance survives every lease, including local refusal.
  stream.preparation

func planFacts*(plan: FlatPlan): uint64 =
  ## Immutable decoded-fact occupancy belongs to the admitted source owner.
  uint64(plan.facts.len)

proc prepareFlatMemoryFrame*(plan: FlatPlan, memory: Memory, info: MachineInfo): FlatResult[FlatFrame] =
  ## A validated immutable Memory already owns checked page capabilities; retain it instead of recapturing them.
  let count = memoryPageCount(memory)
  if count.error != MachineError.None: return FlatResult[FlatFrame](status: FlatError.InvalidMemory)
  if uint32(count.value) > uint32(plan.limits.pages):
    return FlatResult[FlatFrame](status: FlatError.PageLimitExceeded)
  let images = memoryImages(memory)
  if images.error != MachineError.None: return FlatResult[FlatFrame](
      status: FlatError.InvalidMemory)
  FlatResult[FlatFrame](status: FlatError.None, completed: buildFlatFrame(plan, images.value, info, memory))

proc selectFlatPrices*(f: var FlatFrame, plan: GasPlan, memo: GasMemo): oracle.StepError =
  ## Complete and lazy policy owners must match the exact immutable program before any execution.
  if gasPlanInfo(plan).error == GasPlanError.None:
    if not matchesProgram(plan, f.plan.source): return oracle.StepError.InvalidGasPlan
    f.pricingPlan = plan
    f.pricingKind = 1
  elif gasMemoInfo(memo).error == GasMemoError.None:
    if not matchesProgram(memo, f.plan.source): return oracle.StepError.InvalidGasMemo
    f.pricingMemo = memo
    f.pricingKind = 2
  oracle.StepError.None
