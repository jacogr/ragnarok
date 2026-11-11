# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## ARM64 scalar, guarded-memory and connected-block lowering with prepared source proofs.
## Code borrows invocation registers and guarded private memory; no invocation/source pointer is retained.
## Prepared execution publishes through the shared asynchronous worker. The direct region,
## mixed-memory and macro owners still exercise the former ARM64 ABIs in native tests.
## A direct publisher does not grant admission to a prepared frame.

import std/assertions
import ../[program, machine]
import ./native_register_ring
import ./jit_rules
import ./[native_control, native_ir]
import ./native_read_body
when NativeReadCycleEnabled:
  import ./[native_read_cycle, native_read_window]

when defined(pvmArmMixedGroupReceipt):
  const armMixedStateWords = 7
else:
  const armMixedStateWords = 5

type ArmMixedState* = array[armMixedStateWords, uint64]

type ArmReadContext* = array[6, array[3, uint64]]
  ## One frame-owned full context: raw descriptor triplets first, clipped read triplets second.

const armMacroStateWords* = 26
type ArmMacroState* = array[armMacroStateWords, uint64]

proc armClock*(): uint64 {.cdecl, importc: "pvm_arm64_jit_cpu_ns", header: "arm64_memory.h".}
  ## Read the native CPU-time counter used to measure ARM64 JIT work.

proc createArenaNative(): nil pointer {.cdecl, importc: "pvm_arm64_arena_create",
    header: "arm64_memory.h".}
  ## Allocate one native executable arena, returning nil when allocation is unavailable.

proc destroyArena(arena: nil pointer) {.cdecl, importc: "pvm_arm64_arena_destroy",
    header: "arm64_memory.h".}
  ## Release the native arena and its executable-memory ownership.

proc publishArena(arena: nil pointer, words: pointer,
    count: uint32): int32 {.cdecl, importc: "pvm_arm64_arena_publish", header: "arm64_memory.h".}
  ## Publish the supplied instruction words through the native arena permission boundary.

proc callArena(arena: nil pointer, offset: uint32,
    registers: pointer): cint {.cdecl, importc: "pvm_arm64_arena_call", header: "arm64_memory.h".}
  ## Execute a published entry with a borrowed register file and return its native status.

proc nextArena(arena: nil pointer, offset: uint32,
    registers: pointer): uint32 {.cdecl, importc: "pvm_arm64_arena_next", header: "arm64_memory.h".}
  ## Execute an entry and return its next control-flow offset without retaining registers.

proc regionArena(arena: nil pointer, offset: uint32, registers, state: pointer): uint32 {.cdecl,
    importc: "pvm_arm64_arena_region", header: "arm64_memory.h".}
  ## Execute a published region with borrowed registers and region accounting state.

type
  ArmEntryRecord = object ## Executable records bind code, operation count and successor; uncompiled headers may hold a bounded probe budget.
    code, operations, ending: uint32
  ArmMacroChildRecord* = object ## Read-only scalar view of an existing same-owner child entry.
    code*, operations*, ending*: uint32
  ArmMacroShape* = object ## One observed source graph, with no invocation pointer or diagnostic PC.
    cycleHeader*, cycleExit*: uint32
    staticHeader*, staticTarget*: uint32
    pureHeader*, pureBody*, pureTerminal*, pureYes*, pureNo*: uint32
    branchHeader*, branchYes*, branchNo*: uint32
    readHeader*, readBody*, readTerminal*, terminalTarget*: uint32
    staticSpan*, pureSpan*, branchSpan*, readSpan*: uint32
    staticPrice*, purePrice*, branchPrice*, readPrice*: uint64
    branchSlot*: range[0..12]
    branchImmediate*: uint64
  ArmMacroCache = object ## Separate code offset and semantic counts never displace a child entry.
    status: uint8
    residentMode: bool
    probeVisits: uint8
    code: uint32
    imageWords: uint32
    shape: ArmMacroShape
    cycleCode, pureCode, readCode, pureOperations, readOperations: uint32
    calls, cycleChildCalls, staticBlocks, pureBlocks, branchBlocks, readBlocks,
      readRefusals: uint64
  ArmRegionCache = object ## One bounded connected loop retains only exact-source scalar proofs and counters.
    status: uint8
    headers, spans, operations: array[3, uint32]
    prices: array[3, uint64]
    calls, blocks: uint64
    blockCount: uint32 # Active two/three-block shape; unused counter lanes remain zero.
  ArmDirtyLoopCache = object ## Independent one-block cache cannot displace the existing connected region.
    status: uint8
    header, span, operations, code: uint32
    price, calls, blocks, declines, wordGroups: uint64
  ArmMemoryCycleCache = object ## One source-shaped driver either links or inlines sealed dirty/read children.
    status: uint8
    residentMode: bool
    prefixHeader, dirtyHeader, tailHeader, other: uint32
    prefixSpan, tailSpan, prefixOperations, tailOperations: uint32
    prefixPrice, tailPrice: uint64
    calls, prefixBlocks, tailBlocks, dirtyBlocks, wordGroups, dirtyCalls: uint64
  ArmBlock* = object ## A bounded leaf keeps guest registers in X4–X16, loading live-ins and publishing only dirty slots.
    words, terminal: seq[uint32]
    reads, writes: uint32
    compact: bool
  ArmReadGuard = object ## A code-relative refusal edge publishes no speculative register prefix.
    at: int
    conditional: bool
  ArmReadSpan* = object ## Cold-only builder; all reads and arithmetic commit their guest registers together.
    body: ArmBlock
    guards: seq[ArmReadGuard]
    directFirst: bool
    clippedReads: bool # Source-constant read mode; whole-window bodies retain raw descriptors.
    branchReady: bool
    branchYes, branchNo: uint32
  ArmMixedSite = object
    operation, completed, writes: uint32
  ArmMixedFixup = object
    at, site: int
    condition: uint32
  ArmMixedBlock* = object ## One charged source body with exact paid-memory exits.
    body: ArmBlock
    sites: seq[ArmMixedSite]
    fixes: seq[ArmMixedFixup]
    lowered: uint32
  ArenaOwner = object ## Move-only OS allocation; the containing reference shares no mutable invocation state.
    handle: nil pointer
  ArmJit* = ref object ## Exclusive frame-owned compiler cache; no executable image escapes its arena owner.
    arena: ArenaOwner
    region: ArmRegionCache
    dirtyLoop: ArmDirtyLoopCache
    entries: seq[ArmEntryRecord]
    branchCalls*, headerCalls*: uint64
    fragments*: uint64
    calls*, operations*, codeBytes*, compilationNs*: uint64
    unavailable: bool
    clippedReads: bool # Uniform owner mode keeps the twelve-byte entry record unchanged.
    mixedCalls*, mixedCompleted*, mixedInterior*, mixedOperations*: uint64
    mixedGroupPublished, mixedGroupAttempts, mixedGroupPasses: uint64
    memoryCycle: ArmMemoryCycleCache
    macroRoute: ArmMacroCache

proc `=copy`(destination: var ArenaOwner, source: ArenaOwner) {.error.}
  ## Reject copying the exclusive native executable arena owner.

proc `=dup`(source: ArenaOwner): ArenaOwner {.error.}
  ## Reject duplication of the exclusive native executable arena owner.

proc `=wasMoved`(owner: var ArenaOwner) {.nodestroy, inline.} =
  ## A moved native handle has no allocation left to release.
  owner.handle = nil

when defined(pvmArmDirtyLoopOwnerReceipt):
  var armArenaDestroyedCount {.threadvar.}: uint64

  proc armDirtyLoopArenaDestroyed*(): uint64 =
    armArenaDestroyedCount

proc `=destroy`(owner: ArenaOwner) =
  ## A default or moved-from owner has no executable mapping to release.
  if owner.handle != nil:
    when defined(pvmArmDirtyLoopOwnerReceipt): inc armArenaDestroyedCount
    destroyArena(owner.handle)

proc createArena(): nil pointer =
  ## Local refusal controls prove that unavailable executable storage preserves checked fallback.
  when defined(pvmArm64JitRefuse): nil
  else: createArenaNative()

proc newArmJit*(clippedReads: bool = false): ArmJit =
  ## Fix the read-context policy for this code owner before any image is published.
  # Keep the same three-u32 logical payload per stream coordinate, without hidden record padding.
  assert sizeof(ArmEntryRecord) == 12
  ArmJit(arena: ArenaOwner(handle: nil), region: default(ArmRegionCache),
      dirtyLoop: default(ArmDirtyLoopCache), entries: @[], unavailable: false,
      clippedReads: clippedReads, memoryCycle: default(ArmMemoryCycleCache),
      macroRoute: default(ArmMacroCache))

func armUsesClippedReads*(jit: ArmJit): bool =
  ## Read images share one immutable owner policy across ordinary and nested entry routes.
  jit != nil and jit.clippedReads

proc armUseClippedReads*(span: var ArmReadSpan, jit: nil ArmJit) =
  ## Select the full-context read table before emitting any individual scalar access.
  assert jit != nil
  if jit == nil: return
  assert jit.clippedReads and span.body.words.len == 0
  span.clippedReads = true

func supportedArmOpcode*(opcode: byte): bool {.inline.} =
  ## Non-exiting arithmetic remains independent of guest memory, branch selection and source accounting.
  supportedScalarOpcode(opcode)

func newArmRegionBody*(): ArmBlock =
  ## Connected bodies have their own measured constant policy; ordinary fragment layout stays unchanged.
  result = default(ArmBlock)
  result.compact = true

proc armRead(fragment: var ArmBlock, slot: range[0..12]): uint32 =
  ## An operand needs an initial load only before the fragment's first write to that same guest slot.
  let bit = (1'u32 shl int(slot))
  if (fragment.writes and bit) == 0: fragment.reads = fragment.reads or bit
  uint32(slot)+4

proc armWrite(fragment: var ArmBlock, slot: range[0..12]): uint32 =
  ## A dirty resident register is committed exactly once before the leaf returns to checked execution.
  fragment.writes = fragment.writes or (1'u32 shl int(slot))
  uint32(slot)+4

proc emitArmDirtyRegionByteStore*(body: var ArmBlock, valueSlot: range[0..12]) =
  ## Track a store-only live-in as well as values produced by the arithmetic prefix.
  let value = armRead(body, valueSlot)
  body.words.add(0x9e660001'u32) # FMOV X1,D0.
  body.words.add(0x39000020'u32 or value)

proc armImmediate(words: var seq[uint32], destination: uint32, value: uint64) =
  ## Explicit halfwords preserve all immediate bits, without host signed conversions or shifts by the width.
  assert destination <= 16
  words.add(0xd2800000'u32 or (uint32(value and 65535) shl 5) or destination)
  for half in 1..3:
    words.add(0xf2800000'u32 or (uint32(half) shl 21) or
        (uint32((value shr (half*16)) and 65535) shl 5) or destination)

proc armCompactImmediate(words: var seq[uint32], destination: uint32, value: uint64) =
  ## Choose MOVZ or MOVN plus only differing halfwords; every sequence initializes all sixty-four bits.
  assert destination <= 16
  var zeroParts = 0
  var oneParts = 0
  for half in 0..<4:
    # Counts bound the exact instruction costs of zero-filled and one-filled initial values.
    let part = uint32((value shr (half*16)) and 65535)
    if part != 0: inc zeroParts
    if part != 65535: inc oneParts
  let inverted = oneParts < zeroParts
  let fill = if inverted: 65535'u32 else: 0'u32
  var initialized = false
  for half in 0..<4:
    # The first changed halfword initializes every other halfword; later MOVK instructions preserve them.
    let part = uint32((value shr (half*16)) and 65535)
    if part == fill: continue
    let operation = if initialized: 0xf2800000'u32
      elif inverted: 0x92800000'u32 else: 0xd2800000'u32
    let payload = if not initialized and inverted: part xor 65535'u32 else: part
    words.add(operation or (uint32(half) shl 21) or (payload shl 5) or destination)
    initialized = true
  if not initialized:
    # Zero and all-ones still require one defining instruction, regardless of the incoming host register.
    words.add((if inverted: 0x92800000'u32 else: 0xd2800000'u32) or destination)

proc armOperandImmediate(fragment: var ArmBlock, destination: uint32, value: uint64) =
  ## Arithmetic constants define all bits independently of the fixed conditional return selector.
  if fragment.compact: armCompactImmediate(fragment.words, destination, value)
  else: armImmediate(fragment.words, destination, value)

proc emitArmShiftPair*(fragment: var ArmBlock, first, second: RegisterSlots,
    firstImmediate, secondImmediate: uint64): bool =
  ## Decline without mutation unless LSL64/LSR64 overwrite one destination with equal masked counts; full-block admission hides the intermediate value.
  if first.destinationIndex != second.destinationIndex or second.bIndex != first.destinationIndex or
      (firstImmediate and 63) != (secondImmediate and 63): return false
  let source = armRead(fragment, first.bIndex)
  let destination = armWrite(fragment, first.destinationIndex)
  let amount = uint32(firstImmediate and 63)
  # UBFM extracts exactly the low64-k bits; k=0 is a full-width copy and no instruction changes NZCV.
  fragment.words.add(0xd3400000'u32 or ((63'u32-amount) shl 10) or (source shl 5) or destination)
  true

proc emitArmOperation*(fragment: var ArmBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  ## Each instruction consumes original operands before declaring its destination; native aliases obey GP ordering.
  assert supportedArmOpcode(opcode)
  if opcode in [20'u8, 51]:
    # Immediate loads have no register live-in; their destination may previously be undefined in the leaf.
    let destination = armWrite(fragment, slots.destinationIndex)
    armOperandImmediate(fragment, destination, immediate)
    return
  if opcode == 100 or opcode in {107'u8..110'u8}:
    # Unary operations read the genuine A slot; every result is full-width, including signed extension.
    let source = armRead(fragment, slots.aIndex)
    let destination = armWrite(fragment, slots.destinationIndex)
    let operation = case opcode
      of 107: 0x93401c00'u32 # SXTB Xd,Wn
      of 108: 0x93403c00'u32 # SXTH Xd,Wn
      of 109: 0xd3403c00'u32 # UXTH Xd,Xn
      of 110: 0xdac00c00'u32 # REV Xd,Xn
      else: 0xaa0003e0'u32   # MOV Xd,Xn (ORR Xd,XZR,Xn)
    fragment.words.add(operation or (source shl (if opcode == 100: 16 else: 5)) or destination)
    return
  if opcode in {138'u8..140'u8, 151'u8..153'u8}:
    # Bitfield-immediate shifts use the same masked counts as the variable shifts.
    # Read the original B before recording A so aliased operands retain GP ordering.
    let source = armRead(fragment, slots.bIndex)
    let destination = armWrite(fragment, slots.destinationIndex)
    let wordShift = opcode <= 140
    let width = if wordShift: 32'u32 else: 64'u32
    let count = uint32(immediate and uint64(width-1))
    let base = if opcode in {138'u8, 139, 151, 152}:
      (if wordShift: 0x53000000'u32 else: 0xd3400000'u32)
      else: (if wordShift: 0x13000000'u32 else: 0x93400000'u32)
    let immr = if opcode in {138'u8, 151}: (width-count) and (width-1) else: count
    let imms = if opcode in {138'u8, 151}: width-1-count else: width-1
    fragment.words.add(base or (immr shl 16) or (imms shl 10) or
        (source shl 5) or destination)
    if wordShift:
      # GP signed-word results extend the low 32 bits, including count zero.
      fragment.words.add(0x93407c00'u32 or (destination shl 5) or destination)
    return
  var left = 0'u32
  var right = 0'u32
  if opcode < 190:
    # Immediate arithmetic reads B; X1 is scratch and cannot alias the resident guest register bank.
    left = armRead(fragment, slots.bIndex)
    armOperandImmediate(fragment, 1, immediate)
    right = 1
  else:
    # Three-register arithmetic snapshots both source coordinates before recording a destination write.
    left = armRead(fragment, slots.aIndex)
    right = armRead(fragment, slots.bIndex)
  if opcode in [141'u8, 154]:
    # Negated-add immediate is immediate minus B, preserving operand order without an intermediate mutation.
    let original = left
    left = right
    right = original
  let destination = armWrite(fragment, slots.destinationIndex)
  if opcode in {136'u8, 137, 142, 143, 216, 217}:
    # CMP consumes both original operands before CSET zero-extends a literal Boolean into an aliased destination.
    let condition = case opcode
      of 136, 216: 3'u32  # LO: unsigned less.
      of 137, 217: 11'u32 # LT: signed less.
      of 142: 8'u32       # HI: unsigned greater.
      else: 12'u32        # GT: signed greater.
    fragment.words.add(0xeb00001f'u32 or (right shl 16) or (left shl 5))
    fragment.words.add(0x1a9f07e0'u32 or ((condition xor 1'u32) shl 12) or destination)
    return
  if opcode == 215:
    # Form sign(A)&B in scratch before UMULH can overwrite either source; mixed signedness subtracts this correction.
    fragment.words.add(0x937ffc01'u32 or (left shl 5)) # ASR X1,Xn,#63.
    fragment.words.add(0x8a000021'u32 or (right shl 16)) # AND X1,X1,Xm.
  let operation = case opcode
    of 213: 0x9b407c00'u32      # SMULH Xd,Xn,Xm.
    of 214, 215: 0x9bc07c00'u32 # UMULH Xd,Xn,Xm; mixed signedness corrects below.
    of 131, 190: 0x0b000000'u32 # ADD Wd,Wn,Wm
    of 141, 191: 0x4b000000'u32 # SUB Wd,Wn,Wm
    of 135, 192: 0x1b007c00'u32 # MUL Wd,Wn,Wm
    of 138, 197: 0x1ac02000'u32 # LSLV Wd,Wn,Wm, count modulo 32
    of 139, 198: 0x1ac02400'u32 # LSRV Wd,Wn,Wm, count modulo 32
    of 140, 199: 0x1ac02800'u32 # ASRV Wd,Wn,Wm
    of 160, 223: 0x1ac02c00'u32 # RORV Wd,Wn,Wm
    of 132, 210: 0x8a000000'u32 # AND Xd,Xn,Xm
    of 133, 211: 0xca000000'u32 # EOR Xd,Xn,Xm
    of 134, 212: 0xaa000000'u32 # ORR Xd,Xn,Xm
    of 154, 201: 0xcb000000'u32 # SUB Xd,Xn,Xm
    of 150, 202: 0x9b007c00'u32 # MUL Xd,Xn,Xm
    of 151, 207: 0x9ac02000'u32 # LSLV Xd,Xn,Xm, count modulo 64
    of 152, 208: 0x9ac02400'u32 # LSRV Xd,Xn,Xm
    of 153, 209: 0x9ac02800'u32 # ASRV Xd,Xn,Xm
    of 158, 222: 0x9ac02c00'u32 # RORV Xd,Xn,Xm
    of 224: 0x8a200000'u32      # BIC Xd,Xn,Xm
    of 225: 0xaa200000'u32      # ORN Xd,Xn,Xm
    of 226: 0xca200000'u32      # EON Xd,Xn,Xm
    else: 0x8b000000'u32        # ADD Xd,Xn,Xm
  fragment.words.add(operation or (right shl 16) or (left shl 5) or destination)
  if opcode == 215:
    # The correction is already independent of aliased source registers; subtraction wraps to the exact upper word.
    fragment.words.add(0xcb010000'u32 or (destination shl 5) or destination)
  if opcode in {131'u8, 135, 138..141, 160, 190..192, 197..199, 223}:
    # ARM word operations zero high bits; GP requires sign extension of the low 32-bit result.
    fragment.words.add(0x93407c00'u32 or (destination shl 5) or destination)

proc armBranchCompare(fragment: var ArmBlock, opcode: byte, leftSlot,
    rightSlot: range[0..12], immediate: uint64): uint32 =
  ## Emit the original full-width comparison and return its A64 condition.
  assert opcode in {81'u8..90'u8, 170'u8..175'u8}
  let left = armRead(fragment, leftSlot)
  var right = 1'u32
  if opcode <= 90:
    # Branch immediates retain GP signed low-word extension before full 64-bit comparison.
    # Keep ordinary branch layout fixed; a connected body owns a variable-length defining compare prefix.
    if fragment.compact: armCompactImmediate(fragment.terminal, 1, immediate)
    else: armImmediate(fragment.terminal, 1, immediate)
  else:
    right = armRead(fragment, rightSlot)
  fragment.terminal.add(0xeb00001f'u32 or (right shl 16) or (left shl 5)) # CMP Xn,Xm
  result = case opcode
    of 81, 170: 0'u32 # EQ
    of 82, 171: 1'u32 # NE
    of 83, 172: 3'u32 # CC, unsigned less
    of 84: 9'u32 # LS, unsigned less or equal
    of 85, 174: 2'u32 # CS, unsigned greater or equal
    of 86: 8'u32 # HI, unsigned greater
    of 87, 173: 11'u32 # LT, signed less
    of 88: 13'u32 # LE, signed less or equal
    of 89, 175: 10'u32 # GE, signed greater or equal
    else: 12'u32 # GT, signed greater

proc emitArmBranchSlots(fragment: var ArmBlock, opcode: byte, leftSlot,
    rightSlot: range[0..12], immediate: uint64, yes, no: uint32) =
  ## Positive cached branch capabilities supply scalar destinations. MOV and STR preserve NZCV.
  assert yes < 2147483646'u32 and no < 2147483646'u32
  let condition = armBranchCompare(fragment, opcode, leftSlot, rightSlot, immediate)
  fragment.terminal.add(0x52800001'u32 or ((yes and 65535) shl 5))
  fragment.terminal.add(0x72a00001'u32 or ((yes shr 16) shl 5))
  fragment.terminal.add(0x52800002'u32 or ((no and 65535) shl 5))
  fragment.terminal.add(0x72a00002'u32 or ((no shr 16) shl 5))
  fragment.terminal.add(0x1a820020'u32 or (condition shl 12)) # CSEL W0,W1,W2,cond

proc emitArmBranch*(fragment: var ArmBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64, yes, no: uint32) =
  ## The public decoded-slot path shares the exact compare/selection emitter.
  emitArmBranchSlots(fragment, opcode, slots.aIndex, slots.bIndex,
      immediate, yes, no)

proc armInstructions*(fragment: ArmBlock): seq[uint32] =
  ## Prologue loads only original values needed by this fragment; epilogue publishes every changed guest slot.
  result = @[]
  for slot in 0..<13:
    if (fragment.reads and (1'u32 shl int(slot))) != 0:
      result.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  for word in fragment.words: result.add(word)
  for slot in 0..<13:
    if (fragment.writes and (1'u32 shl int(slot))) != 0:
      result.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  for word in fragment.terminal: result.add(word)

type ArmLoopFixup = object ## One symbolic branch displacement in the common control program.
  at: int
  target: LoopLabel
  instruction: uint32

proc armLoopEdge(words: var seq[uint32], fixes: var seq[ArmLoopFixup],
    target: LoopLabel, instruction: uint32) =
  ## B or B.cond placeholder has a zero instruction-relative displacement.
  fixes.add(ArmLoopFixup(at: words.len, target: target, instruction: instruction))
  words.add(instruction) # B imm26=0 or B.cond imm19=0; condition is already selected by the action.

proc encodeArmLoop*(span: NativeSpan, control: LoopControl): seq[uint32] =
  ## Lower shared actions using caller-saved registers and a resident guest register bank.
  let loop = span.loopInfo
  var body = default(ArmBlock)
  for index in 0..<span.len:
    # Reuse canonical scalar emission and its read-before-write tracking.
    let op = span.operation(index)
    emitArmOperation(body, op.opcode, op.slots, op.immediate)
  let left = armRead(body, loop.slots.aIndex)
  let right = if loop.rightKind == NativeLoopRightKind.Immediate: 1'u32
    else: armRead(body, loop.slots.bIndex)
  var labels = default(array[LoopLabel, int])
  var fixes: seq[ArmLoopFixup] = @[]
  result = @[]
  for action in control:
    # Register assignment: X0 guest base, X17 context, X2/X3 gas/quota, D16 visits.
    case action.kind
    of LoadContext:
      result.add(0xaa0103f1'u32) # MOV X17,X1: preserve incoming context across scalar scratch use.
      result.add(0xf9400222'u32) # LDR X2,[X17,#0]: gas.
      result.add(0xf9400623'u32) # LDR X3,[X17,#8]: remaining source attempts.
      result.add(0x9e6703f0'u32) # FMOV D16,XZR: zero integer visit bits.
      result.add(0xd2800021'u32) # MOVZ X1,#1: integer increment.
      result.add(0x9e670031'u32) # FMOV D17,X1: preserve increment bits across scalar operations.
    of LoadGuest:
      # The final comparison also contributes original live-ins through armRead above.
      for slot in 0..<13:
        if (body.reads and (1'u32 shl slot)) != 0:
          # LDR X(slot+4),[X0,#slot*8]; scaled imm12 is the original guest slot.
          result.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
    of Label:
      labels[action.target] = result.len
    of ExecuteBody:
      # Copy the canonical scalar instructions verbatim with X1 scratch and X4..X16 guest lanes.
      for word in body.words: result.add(word)
    of CountVisit:
      result.add(0x5ef18610'u32) # ADD D16,D16,D17: integer visits += 1.
    of BranchGuestAboveEqual:
      if loop.rightKind == NativeLoopRightKind.Immediate:
        # MOVZ/MOVN X1,imm16 plus MOVK halfwords defines the exact uint64 comparison operand.
        armCompactImmediate(result, 1, loop.rightImmediate)
      # CMP Xleft,Xright: guest slots use slot+4, and the immediate uses X1.
      result.add(0xeb00001f'u32 or (right shl 16) or (left shl 5))
      armLoopEdge(result, fixes, action.target, 0x54000002'u32) # B.HS to the action label.
    of BranchLaneBelow, DebitLane:
      let lane = if action.lane == Gas: 2'u32 else: 3'u32
      if action.value <= 4095:
        # The unsigned amount fits the unshifted imm12 of CMP/SUB.
        let operand = (uint32(action.value) shl 10) or (lane shl 5)
        if action.kind == BranchLaneBelow:
          result.add(0xf100001f'u32 or operand) # CMP Xlane,#amount; XZR discards subtraction.
        else:
          result.add(0xd1000000'u32 or operand or lane) # SUB Xlane,Xlane,#amount.
      else:
        # MOVZ X1,lo16; MOVK X1,part16,LSL #16/#32/#48 defines the full amount.
        armImmediate(result, 1, action.value)
        if action.kind == BranchLaneBelow:
          result.add(0xeb01001f'u32 or (lane shl 5)) # CMP Xlane,X1.
        else:
          result.add(0xcb010000'u32 or (lane shl 5) or lane) # SUB Xlane,Xlane,X1.
      if action.kind == BranchLaneBelow:
        armLoopEdge(result, fixes, action.target, 0x54000003'u32) # B.LO to the action label.
    of Jump:
      armLoopEdge(result, fixes, action.target, 0x14000000'u32) # B to the action label.
    of SelectReturn:
      # MOVZ X1,lo16; MOVK X1,part16,LSL #16/#32/#48 holds the return coordinate.
      armImmediate(result, 1, action.value)
    of StoreGuest:
      # Commit dirty guest lanes before overwriting the X0 array base.
      for slot in 0..<13:
        if (body.writes and (1'u32 shl slot)) != 0:
          # STR X(slot+4),[X0,#slot*8]; scaled imm12 is the original guest slot.
          result.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
    of StoreContext:
      result.add(0xf9000222'u32) # STR X2,[X17,#0]: gas.
      result.add(0xf9000623'u32) # STR X3,[X17,#8]: quota.
      result.add(0xfd000a30'u32) # STR D16,[X17,#16]: integer visit bits.
    of Return:
      result.add(0x2a0103e0'u32) # MOV W0,W1: return the selected uint32 stream coordinate.
      result.add(0xd65f03c0'u32) # RET X30: leaf return through the caller's link register.
  if result.len > NativeImageByteLimit div 4: return @[]
  for fix in fixes:
    # The complete image cap proves both signed ranges. ARM counts words from the branch itself.
    let delta = cast[uint32](int32(labels[fix.target]-fix.at))
    if fix.instruction == 0x14000000'u32:
      result[fix.at] = fix.instruction or (delta and 0x03ffffff'u32) # B imm26 in bits 25:0.
    else:
      result[fix.at] = fix.instruction or ((delta and 0x7ffff'u32) shl 5) # B.cond imm19 in 23:5.

proc newArmMixedBody*(): ArmMixedBlock =
  ## The checked header has already reserved the complete source block.
  result = default(ArmMixedBlock)
  result.body.compact = true

proc emitArmMixedPure*(mixed: var ArmMixedBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  emitArmOperation(mixed.body, opcode, slots, immediate)
  inc mixed.lowered

proc armMixedGuard(mixed: var ArmMixedBlock, site: int, condition: uint32) =
  assert site >= 0 and site < mixed.sites.len and condition <= 16
  mixed.fixes.add(ArmMixedFixup(at: mixed.body.words.len, site: site, condition: condition))
  mixed.body.words.add(0)

proc armMixedDirtyPage(mixed: var ArmMixedBlock, site: int) =
  ## X3 is a proved address. A clean or absent bitmap word must use the checked store.
  template words: untyped = mixed.body.words
  words.add(0xd352fc62'u32) # LSR X2,X3,#18: sixty-four pages per bitmap word.
  words.add(0xf9400a21'u32) # LDR X1,[X17,#16]: borrowed word count.
  words.add(0xeb01005f'u32) # CMP X2,X1.
  armMixedGuard(mixed, site, 2) # HS: outside bitmap.
  words.add(0xf9400e21'u32) # LDR X1,[X17,#24]: borrowed bitmap pointer.
  words.add(0xf100003f'u32) # CMP X1,#0.
  armMixedGuard(mixed, site, 0)
  words.add(0x8b020c21'u32) # ADD X1,X1,X2,LSL #3.
  words.add(0xf9400021'u32) # LDR X1,[X1].
  words.add(0xd34cfc62'u32) # LSR X2,X3,#12: source page.
  words.add(0xd2800023'u32) # MOV X3,#1.
  words.add(0x9ac22062'u32) # LSLV X2,X3,X2 (hardware masks the shift to six bits).
  words.add(0xea02003f'u32) # TST X1,X2.
  armMixedGuard(mixed, site, 0)

proc emitArmMixedMemory*(mixed: var ArmMixedBlock, opcode: range[120..130],
    slots: RegisterSlots, displacement, operation: uint32) =
  ## Every guard precedes this operation's mutation; earlier stores and register writes stay committed.
  let access = indirectMemoryAccess(opcode)
  let loading = access.kind != IndirectMemoryKind.Store
  let width = access.width
  let site = mixed.sites.len
  mixed.sites.add(ArmMixedSite(operation: operation, completed: mixed.lowered,
      writes: mixed.body.writes))
  let base = armRead(mixed.body, slots.bIndex)
  let value = if loading: 0'u32 else: armRead(mixed.body, slots.aIndex)
  let destination = if loading: armWrite(mixed.body, slots.aIndex) else: 0'u32
  template words: untyped = mixed.body.words
  words.add(0x9e670220'u32) # FMOV D0,X17 saves the context while X17 borrows descriptors.
  words.add(0x2a0003e3'u32 or (base shl 16)) # MOV W3,Wbase.
  words.add(0x52800002'u32 or ((displacement and 65535) shl 5))
  words.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
  words.add(0x0b020063'u32) # ADD W3,W3,W2, modulo 2^32.
  words.add(0xf140407f'u32) # CMP X3,#65536.
  armMixedGuard(mixed, site, 3) # LO: protected prefix.
  armCompactImmediate(words, 2, uint64(high(uint32))-8'u64)
  words.add(0xeb02007f'u32) # CMP X3,X2; conservative complete eight-byte extent.
  armMixedGuard(mixed, site, 8) # HI.
  words.add(0xf9400631'u32) # LDR X17,[X17,#8]: borrowed descriptor pointer.
  var admitted: seq[int] = @[]
  let count = if loading: 3 else: 2
  for region in 0..<count:
    words.add(0xa9400a21'u32 or (uint32(region*3) shl 15)) # LDP Xbase,Xextent.
    words.add(0xcb010061'u32) # SUB Xoffset,Xaddress,Xbase.
    words.add(0xeb02003f'u32) # CMP Xoffset,Xextent; zero extent declines.
    let outside = words.len
    words.add(0)
    words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10)) # LDR Xpointer.
    words.add(0x8b010041'u32) # ADD Xpointer,Xpointer,Xoffset.
    words.add(0x9e670021'u32) # FMOV D1,Xpointer.
    admitted.add(words.len)
    words.add(0)
    let following = words.len
    words[outside] = 0x54000002'u32 or (uint32(following-outside) shl 5)
  armMixedGuard(mixed, site, 16) # No admitted descriptor.
  let accepted = words.len
  for at in admitted: words[at] = 0x14000000'u32 or uint32(accepted-at)
  words.add(0x9e660011'u32) # FMOV X17,D0 restores the context.
  if not loading:
    words.add(0x9e670062'u32) # FMOV D2,X3 saves the first address across bitmap tests.
    armMixedDirtyPage(mixed, site)
    if width > 1:
      words.add(0x9e660043'u32) # FMOV X3,D2.
      words.add(0x91000063'u32 or ((width-1) shl 10)) # ADD X3,X3,#width-1.
      words.add(0xd34cfc62'u32) # LSR X2,X3,#12: final page.
      words.add(0x9e660041'u32) # FMOV X1,D2: first address.
      words.add(0xd34cfc21'u32) # LSR X1,X1,#12: first page.
      words.add(0xeb01005f'u32) # CMP X2,X1.
      let samePage = words.len
      words.add(0)
      armMixedDirtyPage(mixed, site)
      let afterSecond = words.len
      words[samePage] = 0x54000000'u32 or (uint32(afterSecond-samePage) shl 5)
  words.add(0x9e660021'u32) # FMOV X1,D1 restores the admitted byte pointer.
  if loading:
    let encoding = case opcode
      of 124: 0x39400020'u32 # LDRB Wdestination,[X1].
      of 125: 0x39800020'u32 # LDRSB Xdestination,[X1].
      of 126: 0x79400020'u32 # LDRH Wdestination,[X1].
      of 127: 0x79800020'u32 # LDRSH Xdestination,[X1].
      of 128: 0xb9400020'u32 # LDR Wdestination,[X1].
      of 129: 0xb9800020'u32 # LDRSW Xdestination,[X1].
      else: 0xf9400020'u32   # LDR Xdestination,[X1].
    words.add(encoding or destination)
  else:
    let encoding = case opcode
      of 120: 0x39000020'u32 # STRB Wvalue,[X1].
      of 121: 0x79000020'u32 # STRH Wvalue,[X1].
      of 122: 0xb9000020'u32 # STR Wvalue,[X1].
      else: 0xf9000020'u32   # STR Xvalue,[X1].
    words.add(encoding or value)
  inc mixed.lowered

proc emitArmMixedWindowMemory*(mixed: var ArmMixedBlock, opcode: range[120..130],
    slots: RegisterSlots, displacement, operation, minDisp, maxEnd, cacheReg: uint32,
    first, writable: bool) =
  ## A first-site window proof caches only a byte pointer; source values and stores remain ordered.
  assert cacheReg >= 4 and cacheReg <= 16 and minDisp <= displacement and
      maxEnd > displacement and maxEnd-minDisp <= 4096
  let access = indirectMemoryAccess(opcode)
  let loading = access.kind != IndirectMemoryKind.Store
  let width = access.width
  assert uint64(displacement)+uint64(width) <= uint64(maxEnd)
  let site = mixed.sites.len
  mixed.sites.add(ArmMixedSite(operation: operation, completed: mixed.lowered,
      writes: mixed.body.writes))
  let base = armRead(mixed.body, slots.bIndex)
  let value = if loading: 0'u32 else: armRead(mixed.body, slots.aIndex)
  let destination = if loading: armWrite(mixed.body, slots.aIndex) else: 0'u32
  template words: untyped = mixed.body.words
  if first:
    # Form the unwrapped exclusive endpoint before any descriptor subtraction or guest mutation.
    let span = maxEnd-minDisp
    when defined(pvmArmMixedGroupReceipt):
      words.add(0xf9401621'u32) # LDR X1,[X17,#40]: private attempt counter.
      words.add(0x91000421'u32) # ADD X1,X1,#1.
      words.add(0xf9001621'u32) # STR X1,[X17,#40].
    words.add(0x9e670220'u32) # FMOV D0,X17 keeps the invocation context for this site's exit.
    words.add(0x2a0003e3'u32 or (base shl 16)) # MOV W3,Wbase.
    armCompactImmediate(words, 2, uint64(minDisp))
    words.add(0x8b020063'u32) # ADD X3,X3,X2: unwrapped window start.
    words.add(0xf140407f'u32) # CMP X3,#65536.
    armMixedGuard(mixed, site, 3)
    armCompactImmediate(words, 2, uint64(span))
    words.add(0x8b020062'u32) # ADD X2,X3,X2: exclusive endpoint.
    armCompactImmediate(words, 1, uint64(high(uint32))-7'u64)
    words.add(0xeb01005f'u32) # CMP X2,X1: no wrap or protected top.
    armMixedGuard(mixed, site, 8)
    if writable:
      words.add(0xd1000442'u32) # SUB X2,X2,#1: final byte.
      words.add(0xd34cfc61'u32) # LSR X1,X3,#12.
      words.add(0xd34cfc42'u32) # LSR X2,X2,#12.
      words.add(0xeb02003f'u32) # CMP X1,X2: one guest page.
      armMixedGuard(mixed, site, 1)
    words.add(0xf9400631'u32) # LDR X17,[X17,#8]: borrowed descriptors.
    let required = max(span, 8'u32)-7'u32
    var admitted: seq[int] = @[]
    for region in 0..<(if writable: 2 else: 3):
      words.add(0xa9400a21'u32 or (uint32(region*3) shl 15)) # LDP base,extent.
      words.add(0xf100005f'u32 or (required shl 10)) # CMP X2,#required.
      let tooShort = words.len
      words.add(0)
      words.add(0xd1000042'u32 or (required shl 10)) # SUB X2,X2,#required.
      words.add(0xcb010061'u32) # SUB X1,X3,XregionBase.
      words.add(0xeb02003f'u32) # CMP X1,X2.
      let outside = words.len
      words.add(0)
      words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10)) # LDR pointer.
      words.add(0x8b010040'u32 or cacheReg) # ADD Xcache,X2,X1.
      admitted.add(words.len)
      words.add(0)
      let following = words.len
      words[tooShort] = 0x54000003'u32 or (uint32(following-tooShort) shl 5)
      words[outside] = 0x54000008'u32 or (uint32(following-outside) shl 5)
    armMixedGuard(mixed, site, 16)
    let accepted = words.len
    for at in admitted: words[at] = 0x14000000'u32 or uint32(accepted-at)
    words.add(0x9e660011'u32) # FMOV X17,D0: restore invocation context.
    if writable: armMixedDirtyPage(mixed, site) # X3 still holds the first page address.
    when defined(pvmArmMixedGroupReceipt):
      words.add(0xf9401a21'u32) # LDR X1,[X17,#48]: private accepted counter.
      words.add(0x91000421'u32) # ADD X1,X1,#1.
      words.add(0xf9001a21'u32) # STR X1,[X17,#48].
  let delta = displacement-minDisp
  let encoding = case opcode
    of 120: 0x39000020'u32
    of 121: 0x79000020'u32
    of 122: 0xb9000020'u32
    of 123: 0xf9000020'u32
    of 124: 0x39400020'u32
    of 125: 0x39800020'u32
    of 126: 0x79400020'u32
    of 127: 0x79800020'u32
    of 128: 0xb9400020'u32
    of 129: 0xb9800020'u32
    else: 0xf9400020'u32
  let target = if loading: destination else: value
  if delta mod width == 0 and delta div width < 4096:
    words.add((encoding and not (31'u32 shl 5)) or (cacheReg shl 5) or
        ((delta div width) shl 10) or target)
  else:
    if delta <= 4095:
      words.add(0x91000001'u32 or (delta shl 10) or (cacheReg shl 5)) # ADD X1,Xcache,#delta.
    else:
      armCompactImmediate(words, 2, uint64(delta))
      words.add(0x8b020001'u32 or (cacheReg shl 5)) # ADD X1,Xcache,X2.
    words.add(encoding or target)
  inc mixed.lowered

proc emitArmMixedBranch*(mixed: var ArmMixedBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64, yes, no: uint32) =
  emitArmBranch(mixed.body, opcode, slots, immediate, yes, no)
  inc mixed.lowered

func armMixedLowered*(mixed: ArmMixedBlock): uint32 = mixed.lowered

proc armMixedInstructions*(mixed: ArmMixedBlock): seq[uint32] =
  ## One explicit result kind and a constant completed-prefix count certify each native exit.
  assert mixed.body.terminal.len > 0 and mixed.sites.len >= 2
  result = @[0xaa0103f1'u32] # MOV X17,X1, retaining only this call's context.
  var leading = 0
  for slot in 0..<13:
    if (mixed.body.reads and (1'u32 shl slot)) != 0:
      result.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
      inc leading
  for word in mixed.body.words: result.add(word)
  for slot in 0..<13:
    if (mixed.body.writes and (1'u32 shl slot)) != 0:
      result.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  for word in mixed.body.terminal: result.add(word)
  result.add(0xd2800021'u32) # Kind1: complete branch.
  result.add(0xf9000221'u32) # STR X1,[X17].
  result.add(0xd2800001'u32 or (mixed.lowered shl 5))
  result.add(0xf9001221'u32) # Completed lowered operations, context word4.
  result.add(0xd65f03c0'u32)
  var exits = newSeq[int](mixed.sites.len)
  for fix in mixed.fixes:
    # Zero means unreferenced; only guards need a paid-prefix exit label.
    exits[fix.site] = -1
  for index, site in mixed.sites:
    if exits[index] == 0: continue # Later members of a shared window have no guards or exit stubs.
    exits[index] = result.len
    result.add(0x9e660011'u32) # Restore context from D0 even if guard borrowed X17.
    for slot in 0..<13:
      if (site.writes and (1'u32 shl slot)) != 0:
        result.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
    armCompactImmediate(result, 0, uint64(site.operation))
    result.add(0xd2800041'u32) # Kind2: paid interior.
    result.add(0xf9000221'u32)
    result.add(0xd2800001'u32 or (site.completed shl 5))
    result.add(0xf9001221'u32)
    result.add(0xd65f03c0'u32)
  for fix in mixed.fixes:
    assert exits[fix.site] > 0 # Every patched guard names an emitted prefix-specific exit.
    let at = fix.at+leading+1
    let distance = uint32(exits[fix.site]-at)
    assert distance < 262144'u32
    result[at] = if fix.condition == 16: 0x14000000'u32 or distance
      else: 0x54000000'u32 or (distance shl 5) or fix.condition

proc armReadRefusal(span: var ArmReadSpan, word: uint32, conditional: bool) =
  ## Every failed address/extent check branches to one final return without register stores.
  span.guards.add(ArmReadGuard(at: span.body.words.len, conditional: conditional))
  span.body.words.add(word)

func armReadEncoding(opcode: range[124..130]): uint32 =
  ## Unsigned widths clear their unused upper bits; signed widths extend directly into the full64-bit guest register.
  case opcode
  of 124: 0x38606800'u32 # LDRB Wt,[Xn,Xm].
  of 125: 0x38a06800'u32 # LDRSB Xt,[Xn,Xm].
  of 126: 0x78606800'u32 # LDRH Wt,[Xn,Xm].
  of 127: 0x78a06800'u32 # LDRSH Xt,[Xn,Xm].
  of 128: 0xb8606800'u32 # LDR Wt,[Xn,Xm].
  of 129: 0xb8a06800'u32 # LDRSW Xt,[Xn,Xm].
  else: 0xf8606800'u32 # LDR Xt,[Xn,Xm].

proc armSmallIndirectAddress(words: var seq[uint32], source, displacement: uint32,
    alreadyInW3: bool): bool =
  ## A 32-bit ADD/SUB retains the source's modulo-2^32 address, including negative offsets.
  assert source <= 16 and source != 31
  let base = if alreadyInW3: 3'u32 else: source
  if displacement <= 4095'u32:
    if not alreadyInW3 or displacement != 0:
      words.add(0x11000003'u32 or (displacement shl 10) or (base shl 5))
    return true
  if displacement >= 0xfffff001'u32:
    let magnitude = high(uint32)-displacement+1'u32
    words.add(0x51000003'u32 or (magnitude shl 10) or (base shl 5))
    return true
  false

proc emitArmReadFrom(span: var ArmReadSpan, baseSlot, destinationSlot: range[0..12],
    displacement: uint32, opcode: range[124..130], absolute: bool = false) =
  ## Indirect aliases consume the old base; a direct load has the specified immediate address.
  let source = if absolute: 31'u32 else: armRead(span.body, baseSlot)
  let destination = armWrite(span.body, destinationSlot)
  if absolute or not armSmallIndirectAddress(span.body.words, source, displacement, false):
    # Absolute source 31 is WZR in MOV but WSP in ADD-immediate; retain its old path.
    span.body.words.add(0x2a0003e3'u32 or (source shl 16))
    span.body.words.add(0x52800002'u32 or ((displacement and 65535) shl 5))
    span.body.words.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
    span.body.words.add(0x0b020063'u32)
  if not span.clippedReads:
    # Legacy raw descriptors still need the original low and top guards.
    span.body.words.add(0xf140407f'u32)
    armReadRefusal(span, 0x54000003'u32, true)
    span.body.words.add(0x12800102'u32)
    span.body.words.add(0xeb02007f'u32)
    armReadRefusal(span, 0x54000008'u32, true)
  var accepted = default(array[3, int])
  for region in 0..<3:
    # X17 preserves the descriptor base across arithmetic's X1 scratch; X3 retains the address across region misses.
    let descriptor = region*3+(if span.clippedReads: 9 else: 0)
    span.body.words.add(0xa9400a21'u32 or (uint32(descriptor) shl 15)) # LDP base/limit.
    span.body.words.add(0xcb010061'u32) # SUB X1,X3,X1 computes an unsigned region offset.
    span.body.words.add(0xeb02003f'u32) # CMP X1,X2 proves offset < extent-minus-seven.
    span.body.words.add(0x54000082'u32) # HS skips exactly the pointer, load and accepted branch.
    span.body.words.add(0xf9400222'u32 or (uint32(descriptor+2) shl 10)) # Borrowed pointer.
    span.body.words.add(armReadEncoding(opcode) or (1'u32 shl 16) or (2'u32 shl 5) or
        destination) # The unchanged eight-byte extent proof also covers narrower unaligned reads.
    accepted[region] = span.body.words.len
    span.body.words.add(0x14000000'u32)
  armReadRefusal(span, 0x14000000'u32, false) # Missing/fragmented memory replays the complete original prefix.
  let after = span.body.words.len
  for index in accepted:
    # Each admitted region rejoins immediately after this load's guards, never bypassing a later load.
    assert index >= 0 and index < after
    span.body.words[index] = span.body.words[index] or uint32(after-index)

proc emitArmRead*(span: var ArmReadSpan, slots: RegisterSlots, displacement: uint32,
    opcode: range[124..130] = 130) =
  ## Indirect loads read the original B register and publish A only on success.
  span.directFirst = false
  emitArmReadFrom(span, slots.bIndex, slots.aIndex, displacement, opcode)

proc emitArmDirectRead*(span: var ArmReadSpan, slots: RegisterSlots, displacement: uint32,
    opcode: range[52..58]) =
  ## Direct loads have an absolute modulo-2^32 immediate address and publish A only on success.
  span.directFirst = span.body.words.len == 0 and span.guards.len == 0
  emitArmReadFrom(span, slots.aIndex, slots.aIndex, displacement,
      range[124..130](int(opcode)+72), true)

proc beginArmReadWindow*(span: var ArmReadSpan, slot: range[0..12], first, last: uint32) =
  ## A stable guest base admits one nonwrapping readable window before any speculative register mutation.
  span.directFirst = false
  assert not span.clippedReads and span.body.words.len == 0 and
      last >= first and last-first <= 4088
  let distance = last-first
  let source = armRead(span.body, slot)
  span.body.words.add(0x2a0003e3'u32 or (source shl 16)) # MOV W3,Wsource snapshots the original low word.
  span.body.words.add(0x52800002'u32 or ((first and 65535) shl 5))
  span.body.words.add(0x72a00002'u32 or ((first shr 16) shl 5))
  span.body.words.add(0x0b020063'u32) # The first effective address wraps exactly as a source load does.
  span.body.words.add(0xf140407f'u32) # CMP X3,#65536 excludes the protected prefix.
  armReadRefusal(span, 0x54000003'u32, true)
  let limit = 0xfffffff7'u32-distance
  span.body.words.add(0x52800002'u32 or ((limit and 65535) shl 5))
  span.body.words.add(0x72a00002'u32 or ((limit shr 16) shl 5))
  span.body.words.add(0xeb02007f'u32) # The final word must remain below the existing conservative top bound.
  armReadRefusal(span, 0x54000008'u32, true)
  var accepted = default(array[3, int])
  for region in 0..<3:
    # Descriptor length-minus-seven must exceed the whole displacement range before subtraction can be safe.
    span.body.words.add(0xa9400a21'u32 or (uint32(region*3) shl 15))
    span.body.words.add(0xf100005f'u32 or (distance shl 10)) # CMP X2,#distance.
    span.body.words.add(0x54000109'u32) # LS skips the following seven words, leaving X17 as the context.
    span.body.words.add(0xd1000042'u32 or (distance shl 10)) # SUB X2,X2,#distance.
    span.body.words.add(0xcb010061'u32) # SUB X1,X3,X1; a below-region address becomes a large unsigned offset.
    span.body.words.add(0xeb02003f'u32)
    span.body.words.add(0x54000082'u32) # HS skips pointer extraction, pointer addition and acceptance.
    span.body.words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10))
    span.body.words.add(0x8b010051'u32) # ADD X17,X2,X1 retains the admitted first host address across arithmetic.
    accepted[region] = span.body.words.len
    span.body.words.add(0x14000000'u32)
  armReadRefusal(span, 0x14000000'u32, false)
  let after = span.body.words.len
  for index in accepted:
    # A successful descriptor skips all later descriptors before X17 is consumed as a host-window pointer.
    assert index >= 0 and index < after
    span.body.words[index] = span.body.words[index] or uint32(after-index)

proc emitArmWindowRead*(span: var ArmReadSpan, slot: range[0..12], displacement: uint32) =
  ## One earlier whole-window proof covers this aligned relative offset, including an unaligned original base.
  span.directFirst = false
  assert displacement <= 4088 and displacement mod 8 == 0
  let destination = armWrite(span.body, slot)
  span.body.words.add(0xf9400220'u32 or ((displacement div 8) shl 10) or destination)

proc emitArmReadArithmetic*(span: var ArmReadSpan, opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  ## Existing pure operations share the same resident register bank and original wrapping/alias rules.
  emitArmOperation(span.body, opcode, slots, immediate)

proc emitArmReadBranch*(span: var ArmReadSpan, opcode: byte, slots: RegisterSlots,
    immediate: uint64, yes, no: uint32) =
  ## Append an already validated conditional after all speculative reads and register operations.
  span.branchReady = true
  span.branchYes = yes
  span.branchNo = no
  emitArmBranch(span.body, opcode, slots, immediate, yes, no)

type ArmReadImage = object
  words: seq[uint32]
  successAt, refusalAt: int

proc armReadPatchGuards(words: var seq[uint32], span: ArmReadSpan,
    leading, failure: int) =
  ## Standalone and resident renderers share the same source-relative refusal relocation.
  for guard in span.guards:
    let at = guard.at+leading+1
    assert at >= 1 and at < failure
    let distance = uint32(failure-at)
    words[at] = words[at] or (if guard.conditional: distance shl 5 else: distance)

proc armReadImage(span: ArmReadSpan, ending: uint32,
    conditional, residentMode: bool): ArmReadImage =
  ## Share guarded read emission while letting the cycle own guest publication.
  result = default(ArmReadImage)
  assert (span.body.terminal.len > 0) == conditional
  if residentMode: assert conditional
  var words: seq[uint32] = @[0xaa0103f1'u32] # MOV X17,X1 retains borrowed descriptors.
  var leading = 0
  if residentMode:
    # Direct-read guards occur before its first guest write; prior cycle phases remain resident.
    for word in span.body.words: words.add(word)
    for word in span.body.terminal: words.add(word)
    result.successAt = words.len
    words.add(0) # Branch to the cycle's successful-tail continuation.
  else:
    for slot in 0..<13:
      # armInstructions prefixes exactly one original-value load for each live-in guest slot.
      if (span.body.reads and (1'u32 shl slot)) != 0: inc leading
    for word in armInstructions(span.body): words.add(word)
    if not conditional:
      words.add(0x52800000'u32 or ((ending and 65535) shl 5))
      words.add(0x72a00000'u32 or ((ending shr 16) shl 5))
    words.add(0xd65f03c0'u32) # Success returns after complete register publication.
  let failure = words.len
  words.add(0x12800000'u32) # Refusal returns flatStop.
  if residentMode:
    result.refusalAt = words.len
    words.add(0) # Branch to the cycle's gas/source refund.
  assert words.len < 8192 # Sixty-four admitted source operations fit refusal displacements.
  armReadPatchGuards(words, span, leading, failure)
  result.words = move(words)

when NativeCheckedReadEnabled:
  proc emitArmCheckedReadAt(span: var ArmReadSpan, destination: uint32,
      opcode: range[124..130], pointerOnly: bool = false) =
    ## Resolve the full access at X3 in descriptor order. Load the word or
    ## retain its invocation-local address for the caller.
    let width = indirectMemoryAccess(opcode).width
    var accepted = default(array[3, int])
    for region in 0..<3:
      # X3 is the wrapped address. X17 keeps the borrowed context across every arithmetic operation.
      let descriptor = uint32(region*3)
      span.body.words.add(0xa9400a21'u32 or (descriptor shl 15)) # LDP X1,X2,[X17,#base].
      span.body.words.add(0xf1000042'u32 or (width shl 10)) # SUBS X2,X2,#width.
      span.body.words.add(0x540000e3'u32) # B.LO next_descriptor (extent shorter than width).
      # A below-base subtraction wraps above every admitted 32-bit extent.
      span.body.words.add(0xcb010061'u32) # SUB X1,X3,X1.
      span.body.words.add(0xeb02003f'u32) # CMP X1,X2.
      span.body.words.add(0x54000088'u32) # B.HI next_descriptor (offset exceeds the last load).
      span.body.words.add(0xf9400222'u32 or ((descriptor+2) shl 10)) # LDR X2,[X17,#data].
      if pointerOnly:
        span.body.words.add(0x8b010040'u32 or destination) # ADD Xd,X2,X1, without a guest read.
      else:
        span.body.words.add(armReadEncoding(opcode) or (1'u32 shl 16) or (2'u32 shl 5) or
          destination) # Unsigned loads clear upper bits; signed loads extend into the full Xd.
      accepted[region] = span.body.words.len
      span.body.words.add(0x14000000'u32) # B next_operation (patched below).
    armReadRefusal(span, 0x14000000'u32, false) # B refuse (skip the commit epilogue).
    let after = span.body.words.len
    for index in accepted:
      assert index >= 0 and index < after
      span.body.words[index] = span.body.words[index] or uint32(after-index)

  proc emitArmCheckedRead(span: var ArmReadSpan, slots: RegisterSlots, displacement: uint32,
      opcode: range[124..130], absolute: bool) =
    ## Form the address before claiming the destination, including when it aliases the base.
    assert nativeReadOpcode(byte(opcode))
    if absolute:
      # X3 receives the zero-extended source address without reserving a guest base lane.
      armCompactImmediate(span.body.words, 3, uint64(displacement))
    else:
      let source = armRead(span.body, slots.bIndex)
      if not armSmallIndirectAddress(span.body.words, source, displacement, false):
        # The 32-bit ADD wraps even when the captured immediate used a wide encoding.
        armCompactImmediate(span.body.words, 2, uint64(displacement))
        span.body.words.add(0x0b020003'u32 or (source shl 5)) # ADD W3,Wsource,W2.
    let destination = armWrite(span.body, slots.aIndex)
    emitArmCheckedReadAt(span, destination, opcode)

  proc armCheckedReadInstructions*(body: NativeReadBody): seq[uint32] =
    ## Return 1 after committing every staged slot, or UINT32_MAX with no guest writes.
    assert body.complete
    var span = default(ArmReadSpan)
    for index in 0..<body.len:
      let op = body.operation(index)
      let encoding = nativeReadEncodingOpcode(op.opcode)
      if nativeReadOpcode(encoding):
        let opcode = int(encoding)
        assert opcode >= 124 and opcode <= 130
        emitArmCheckedRead(span, op.slots, uint32(op.immediate and 0xffffffff'u64),
          range[124..130](opcode), encoding != op.opcode)
      else:
        emitArmReadArithmetic(span, op.opcode, op.slots, op.immediate)
    result = armReadImage(span, NativeReadSuccess, false, false).words
    result.add(0xd65f03c0'u32) # RET X30 completes the refusal path for direct publication.

proc armMacroReadImage(span: ArmReadSpan): ArmReadImage =
  ## A multi-read resident body branches to its caller's success or rollback continuation.
  result = default(ArmReadImage)
  if span.body.terminal.len != 0 or span.body.words.len == 0 or span.guards.len == 0: return
  var words: seq[uint32] = @[0xaa0103f1'u32] # MOV X17,X1 retains fresh descriptors.
  for word in span.body.words: words.add(word)
  result.successAt = words.len
  words.add(0)
  let failure = words.len
  result.refusalAt = failure
  words.add(0)
  if words.len >= 1024: return default(ArmReadImage)
  armReadPatchGuards(words, span, 0, failure)
  result.words = move(words)

proc armReadInstructions*(span: ArmReadSpan, ending: uint32,
    conditional: bool = false): seq[uint32] =
  ## Direct witness callers receive raw-only images for their legacy 72-byte context.
  assert not span.clippedReads
  result = armReadImage(span, ending, conditional, false).words

proc armReadInstructionsForOwner*(jit: ArmJit, span: ArmReadSpan, ending: uint32,
    conditional: bool = false): seq[uint32] =
  ## A full-context owner may publish clipped individual reads or unchanged raw windows.
  assert jit != nil and (not span.clippedReads or jit.clippedReads)
  result = armReadImage(span, ending, conditional, false).words

proc armMemoryInstructionsImpl(fragment: var ArmBlock, slots: RegisterSlots,
    displacement, ending: uint32, opcode: range[124..130],
    clippedReads: bool): seq[uint32] =
  ## Emit one selected-width read with an owner-selected descriptor table.
  assert fragment.terminal.len == 0
  let destination = armWrite(fragment, slots.aIndex)
  let arithmetic = armInstructions(fragment)
  var leading = 0
  for slot in 0..<13:
    # Preserve the arithmetic live-in loads; the guarded memory word replaces its destination before suffix arithmetic.
    if (fragment.reads and (1'u32 shl slot)) != 0: inc leading
  result = @[]
  for index in 0..<leading: result.add(arithmetic[index])
  result.add(0xb9400003'u32 or (uint32(slots.bIndex) shl 11)) # LDR Waddress,[Xregisters,#slot*8].
  if not armSmallIndirectAddress(result, 3, displacement, true):
    result.add(0x52800002'u32 or ((displacement and 65535) shl 5))
    result.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
    result.add(0x0b020063'u32) # The fallback preserves every full 32-bit displacement.
  var refused: seq[int] = @[]
  if not clippedReads:
    # The clipped table already intersects the raw extent with both canonical bounds.
    result.add(0xf140407f'u32)
    refused.add(result.len)
    result.add(0x54000003'u32)
    result.add(0x12800102'u32)
    result.add(0xeb02007f'u32)
    refused.add(result.len)
    result.add(0x54000008'u32)
  var accepted: seq[int] = @[]
  for region in 0..<3:
    # Unsigned subtraction rejects addresses below a region; offset < length-7 proves the complete eight-byte extent.
    let descriptor = region*3+(if clippedReads: 9 else: 0)
    result.add(0xa9404422'u32 or (uint32(descriptor) shl 15)) # LDP base/limit.
    result.add(0xcb020062'u32) # SUB Xoffset,Xaddress,Xbase.
    result.add(0xeb11005f'u32) # CMP Xoffset,Xextent.
    result.add(0x54000082'u32) # HS skips this region without reading its pointer.
    result.add(0xf9400031'u32 or (uint32(descriptor+2) shl 10)) # Borrowed pointer.
    result.add(armReadEncoding(opcode) or (2'u32 shl 16) or (17'u32 shl 5) or
        destination) # The conservative eight-byte guard admits every selected width safely.
    accepted.add(result.len)
    result.add(0x14000000'u32)
  let missing = result.len
  result.add(0x14000000'u32) # No fast region admitted: canonical handling owns faults and fragmented accesses.
  let body = result.len
  for index in leading..<arithmetic.len: result.add(arithmetic[index])
  result.add(0x52800000'u32 or ((ending and 65535) shl 5))
  result.add(0x72a00000'u32 or ((ending shr 16) shl 5))
  result.add(0xd65f03c0'u32) # Successful publication returns the exact original source successor.
  let failure = result.len
  result.add(0x12800000'u32) # MOV W0,#0xffffffff; the arena appends RET, with guest registers untouched.
  assert result.len < 1024
  for index in refused:
    # Every forward displacement is bounded by the same sub-1024-word publication contract.
    assert index >= 0 and index < failure
    result[index] = result[index] or (uint32(failure-index) shl 5)
  result[missing] = 0x14000000'u32 or uint32(failure-missing)
  for index in accepted:
    assert index >= 0 and index < body
    result[index] = 0x14000000'u32 or uint32(body-index)

proc armMemoryInstructions*(fragment: var ArmBlock, slots: RegisterSlots,
    displacement, ending: uint32, opcode: range[124..130] = 130): seq[uint32] =
  ## Keep the direct witness emitter bound to the original raw descriptor ABI.
  armMemoryInstructionsImpl(fragment, slots, displacement, ending, opcode, false)

proc armMemoryInstructionsForOwner*(jit: ArmJit, fragment: var ArmBlock,
    slots: RegisterSlots, displacement, ending: uint32,
    opcode: range[124..130] = 130): seq[uint32] =
  ## Frame-native scalar reads follow the immutable owner context policy.
  assert jit != nil
  armMemoryInstructionsImpl(fragment, slots, displacement, ending, opcode, jit.clippedReads)

proc armEntry*(jit: ArmJit, offset, extent: uint32): uint32 =
  ## Zero is unexamined, one refused, and code offsets are stored plus two; maps have a hard local ceiling.
  if jit.unavailable or extent > 262144'u32: return 1
  if jit.entries.len < int(extent):
    # Zero-initialized records grow together; no independently sized metadata columns can diverge.
    jit.entries.setLen(int(extent))
  jit.entries[int(offset)].code

proc refuseArmEntry*(jit: ArmJit, offset: uint32) =
  ## A source-bound refusal avoids repeated compilation attempts without changing interpreted semantics.
  if int(offset) < jit.entries.len and jit.entries[int(offset)].code < 2:
    # An unsuccessful replacement never disturbs a previously published tuple.
    jit.entries[int(offset)].code = 1

proc armStartProbe*(jit: ArmJit, header: uint32) =
  ## Only non-executable header records borrow the operation lane for eight cold discovery visits.
  assert int(header) < jit.entries.len
  assert jit.entries[int(header)].code < 2
  jit.entries[int(header)].operations = 8

proc armStartMixedProbe*(jit: ArmJit, header, extent, ending: uint32): bool =
  ## A proved ordinary mixed header may reuse only a nonexecutable refused-noop record.
  if jit.unavailable or extent > 262144'u32 or header >= extent or
      ending <= header or ending >= extent:
    return false
  if jit.entries.len < int(extent): jit.entries.setLen(int(extent))
  let entry = jit.entries[int(header)]
  if entry.code >= 2 or (entry.code == 1 and entry.ending != 0 and
      entry.ending != ending): return false
  jit.entries[int(header)].code = 1
  jit.entries[int(header)].ending = ending
  jit.entries[int(header)].operations = 8
  true

proc armFinishProbe*(jit: ArmJit, header: uint32): bool =
  ## Sealing after the eighth complete visit removes observation from the steady native dispatch.
  assert int(header) < jit.entries.len
  assert jit.entries[int(header)].code < 2
  let remaining = jit.entries[int(header)].operations
  assert remaining > 0 and remaining <= 8
  jit.entries[int(header)].operations = remaining-1
  remaining == 1

proc publishArmEntry*(jit: ArmJit, offset, ending, count: uint32,
    instructions: var seq[uint32], region: bool = false,
    expectedStart: uint64 = high(uint64)): bool =
  ## Reserve one of the 8,192 publication slots for a connected loop; OS/capacity refusal preserves checked execution.
  if jit.unavailable:
    # Only initial allocation refusal is sticky; a cache with any published code can never enter this state.
    refuseArmEntry(jit, offset)
    return false
  let ceiling = if region: 8192'u64 else: 8191'u64
  if jit.fragments >= ceiling or instructions.len == 0 or instructions.len >= 1024:
    refuseArmEntry(jit, offset)
    return false
  if jit.arena.handle == nil:
    # A new owner may retry OS availability; this refused owner avoids repeated allocation and map growth.
    let created = createArena()
    if created == nil:
      jit.unavailable = true
      refuseArmEntry(jit, offset)
      return false
    jit.arena.handle = created
  instructions.add(0xd65f03c0'u32) # RET follows a leaf or the driver's balanced callee-save epilogue.
  let address = publishArena(jit.arena.handle, addr instructions[0], uint32(instructions.len))
  if address < 0:
    refuseArmEntry(jit, offset)
    return false
  # A successful append consumes capacity even if a planned same-arena BL start does not match.
  inc jit.fragments
  jit.codeBytes+=uint64(instructions.len)*4
  if expectedStart != high(uint64) and uint64(address) != expectedStart:
    return false # Never replace a previously published child with a mislinked driver.
  jit.entries[int(offset)] = ArmEntryRecord(code: uint32(address)+2, operations: count,
      ending: ending)
  true

proc callArmEntry*(jit: ArmJit, offset: uint32, registers: var RegisterFile): uint32 =
  ## Borrow the current invocation's exact fixed register array; native code cannot access the rest of its frame.
  assert sizeof(RegisterFile) == 104
  # A deliberate twelve-byte value copy keeps immutable facts stable without retaining a view across the native call.
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  let completed = callArena(jit.arena.handle, entry.code-2, addr registers)
  assert completed == 1
  inc jit.calls
  jit.operations+=uint64(entry.operations)
  entry.ending

proc callArmMemoryCore(jit: ArmJit, offset: uint32, registers: var RegisterFile,
    descriptorPointer: pointer): uint32 =
  ## The code borrows only this frame's descriptors; refusal publishes no guest mutation and charges no lowered operations.
  assert sizeof(RegisterFile) == 104 and descriptorPointer != nil
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  result = regionArena(jit.arena.handle, entry.code-2, addr registers, descriptorPointer)
  assert result == high(uint32) or result == entry.ending
  inc jit.calls
  if result != high(uint32): jit.operations+=uint64(entry.operations)

proc callArmMemory*(jit: ArmJit, offset: uint32, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]]): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmMemoryCore(jit, offset, registers, addr regions)

proc callArmMemoryContext*(jit: ArmJit, offset: uint32, registers: var RegisterFile,
    context: var ArmReadContext): uint32 =
  ## Borrow the complete 144-byte frame context for one full-mode native entry.
  assert jit != nil and jit.clippedReads and sizeof(context) == 144
  callArmMemoryCore(jit, offset, registers, addr context)

proc callArmMemoryBranchCore(jit: ArmJit, offset, yes, no: uint32,
    registers: var RegisterFile, descriptorPointer: pointer): uint32 =
  ## A refused read leaves the original registers untouched; success selects only cached branch arms.
  assert sizeof(RegisterFile) == 104 and descriptorPointer != nil
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  result = regionArena(jit.arena.handle, entry.code-2, addr registers, descriptorPointer)
  assert result == high(uint32) or result == yes or result == no
  inc jit.calls
  if result != high(uint32):
    inc jit.branchCalls
    jit.operations+=uint64(entry.operations)

proc callArmMemoryBranch*(jit: ArmJit, offset, yes, no: uint32,
    registers: var RegisterFile, regions: var array[3, array[3, uint64]]): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmMemoryBranchCore(jit, offset, yes, no, registers, addr regions)

proc armEnding*(jit: ArmJit, offset: uint32): uint32 =
  ## The original fragment's scalar successor identifies the genuine branch node for deferred capability checks.
  jit.entries[int(offset)].ending

proc callArmBranch*(jit: ArmJit, offset: uint32, registers: var RegisterFile): uint32 =
  ## Native branches may select only their two captured positive scalar offsets; the checked adapter validates the result extent.
  assert sizeof(RegisterFile) == 104
  # A deliberate twelve-byte value copy keeps immutable facts stable without retaining a view across the native call.
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  result = nextArena(jit.arena.handle, entry.code-2, addr registers)
  inc jit.calls
  inc jit.branchCalls
  jit.operations+=uint64(entry.operations)

proc callArmMixedCore(jit: ArmJit, header: uint32, registers: var RegisterFile,
    descriptorPointer: pointer, dirtyWords: var seq[uint64],
    state: var ArmMixedState): uint32 =
  ## The checked header owns gas and attempt reservation; native owns only this body's prefix.
  assert sizeof(RegisterFile) == 104 and descriptorPointer != nil
  assert int(header) < jit.entries.len and jit.entries[int(header)].code >= 2
  let entry = jit.entries[int(header)]
  state[0] = 0
  state[1] = cast[uint64](descriptorPointer)
  state[2] = uint64(dirtyWords.len)
  state[3] = 0
  state[4] = 0
  when defined(pvmArmMixedGroupReceipt):
    state[5] = 0
    state[6] = 0
  if dirtyWords.len > 0: state[3] = cast[uint64](addr dirtyWords[0])
  result = regionArena(jit.arena.handle, entry.code-2, addr registers, addr state)
  assert state[0] in [1'u64, 2'u64] and state[4] <= uint64(entry.operations)
  inc jit.calls
  inc jit.headerCalls
  inc jit.mixedCalls
  jit.operations+=state[4]
  jit.mixedOperations+=state[4]
  when defined(pvmArmMixedGroupReceipt):
    jit.mixedGroupAttempts+=state[5]
    jit.mixedGroupPasses+=state[6]
  if state[0] == 1:
    inc jit.branchCalls
    inc jit.mixedCompleted
  elif state[0] == 2: inc jit.mixedInterior

proc callArmMixed*(jit: ArmJit, header: uint32, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var ArmMixedState): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmMixedCore(jit, header, registers, addr regions, dirtyWords, state)

proc callArmMixedContext*(jit: ArmJit, header: uint32, registers: var RegisterFile,
    context: var ArmReadContext, dirtyWords: var seq[uint64],
    state: var ArmMixedState): uint32 =
  ## Borrow the complete 144-byte frame context for one full-mode native entry.
  assert jit != nil and jit.clippedReads and sizeof(context) == 144
  callArmMixedCore(jit, header, registers, addr context, dirtyWords, state)

func armMixedStatistics*(jit: ArmJit): array[4, uint64] =
  [jit.mixedCalls, jit.mixedCompleted, jit.mixedInterior, jit.mixedOperations]

proc armMixedPublishedGroups*(jit: ArmJit, count: uint32) =
  ## Count only successfully published group windows in this private compiler cache.
  jit.mixedGroupPublished+=uint64(count)

func armMixedGroupStatistics*(jit: ArmJit): array[3, uint64] =
  ## Optional native receipt leaves ordinary mixed counters and paid exits unchanged.
  [jit.mixedGroupPublished, jit.mixedGroupAttempts, jit.mixedGroupPasses]

func armMixedOperationCount*(jit: ArmJit, header: uint32): uint32 =
  jit.entries[int(header)].operations

type
  ArmDirtyWordShape* = object ## Frozen role coordinates only; every invocation rechecks values and memory.
    enabled*: bool
    source*, shift*, destination*, base*, bound*: range[0..12]
  ArmRegionBlock* = object ## One sealed charged block; no guest memory or invocation address is retained.
    header*, span*, operations*, yes*, no*: uint32
    price*: uint64
    body*: ArmBlock
  ArmMemoryCycleBlock* = object ## Scalar source graph and frozen reusable phase bodies, without invocation pointers.
    prefixHeader*, dirtyHeader*, tailHeader*, tailEntry*, other*: uint32
    prefixSpan*, tailSpan*, prefixOperations*, tailOperations*: uint32
    prefixPrice*, tailPrice*: uint64
    prefixBody*: ArmBlock
    dirty*: ArmRegionBlock
    dirtyBaseSlot*: range[0..12]
    dirtyDisplacement*: uint32
    dirtyWord*: ArmDirtyWordShape
    tailRead*: ArmReadSpan
  ArmRegionFixup = object ## Code-relative branch relocation, with guard returns kept distinct from internal edges.
    at: int
    target, condition: uint32
    guard: bool

proc armRegionEdge(words: var seq[uint32], fixes: var seq[ArmRegionFixup], target: uint32,
    condition: uint32, guard: bool) =
  ## Capture only immutable scalar destinations; patch signed instruction-relative distances before publication.
  fixes.add(ArmRegionFixup(at: words.len, target: target, condition: condition, guard: guard))
  words.add(0)

func armRegionStatus*(jit: ArmJit): uint8 =
  ## Zero permits bounded candidate probes, one is owner-wide refusal, and two is an immutable published region.
  jit.region.status

func armRegionCount*(jit: ArmJit): range[2..3] =
  ## Only completely published bounded regions expose an active source-block count.
  let count = jit.region.blockCount
  assert jit.region.status == 2 and count >= 2 and count <= 3
  range[2..3](count)

func armRegionHeader*(jit: ArmJit, index: range[0..2]): uint32 =
  ## Guarded exits may reenter only active captured original charged workers.
  assert jit.region.status == 2 and uint32(index) < jit.region.blockCount
  jit.region.headers[index]

func armRegionMatches*(jit: ArmJit, headers, spans: array[3, uint32],
    prices: array[3, uint64]): bool =
  ## Exact scalar charge coordinates must still match before borrowing a new invocation's registers.
  if jit.region.status != 2: return false
  for index in 0..<3:
    # Matching all scalar charges prevents a cached region from crossing a changed pricing context.
    if jit.region.headers[index] != headers[index] or jit.region.spans[index] != spans[index] or
        jit.region.prices[index] != prices[index]: return false
  true

func armRegionChargeMatches*(jit: ArmJit, index: range[0..2], header, span: uint32,
    price: uint64): bool {.inline.} =
  ## Match one complete cached source-charge record without materializing temporary price/span arrays.
  jit.region.status == 2 and jit.region.headers[index] == header and
    jit.region.spans[index] == span and jit.region.prices[index] == price

proc armRegionWords(blocks: array[3, ArmRegionBlock], count: range[2..3],
    rotating: bool): seq[uint32] =
  ## Emit one resident loop with a whole-source guard at each original header.
  # D16..D19 are caller-saved SIMD lanes distinct from the X-register file; integer ADD preserves all 64 counter bits.
  var words: seq[uint32] = @[0xaa0103f1'u32, 0xf9400222'u32, 0xf9400623'u32,
      0xfd400a30'u32, 0xfd400e31'u32, 0xfd401232'u32, 0xd2800021'u32, 0x9e670033'u32]
  var fixes: seq[ArmRegionFixup] = @[]
  var labels = default(array[3, int])
  var exits: seq[uint32] = @[]
  var exitLabels: seq[int] = @[]
  # Union all block reads/writes; block-local live-in inference alone is insufficient across loop paths.
  var resident = 0'u32
  var written = 0'u32
  for index in 0..<count:
    resident = resident or blocks[index].body.reads or blocks[index].body.writes
    written = written or blocks[index].body.writes
  # A guarded exit may precede any write: initialize every lane the epilogue can publish.
  for slot in 0..<13:
    if (resident and (1'u32 shl slot)) != 0:
      words.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  if rotating:
    # The caller validates the entry index. Zero falls through to the first guarded block.
    words.add(0xf9401621'u32) # LDR X1,[X17,#40].
    words.add(0xf100043f'u32) # CMP X1,#1.
    armRegionEdge(words, fixes, blocks[1].header, 0, false)
    words.add(0xf100083f'u32) # CMP X1,#2.
    armRegionEdge(words, fixes, blocks[2].header, 0, false)
  for index in 0..<count:
    # Only bounded complete source spans with an actual terminal branch may enter this narrow region compiler.
    let item = blocks[index]
    if item.span < 2 or item.span > 4095 or item.operations < 2 or item.operations > item.span:
      return @[]
    if item.body.terminal.len notin [6, 10]:
      # Only our explicit regional policy can shorten the compare constant; the final five return words remain fixed.
      if not item.body.compact or item.body.terminal.len < 7 or item.body.terminal.len > 9:
        return @[]
    labels[index] = words.len
    words.add(0xf100007f'u32 or (item.span shl 10)) # CMP Xremaining,#wholeSourceSpan.
    armRegionEdge(words, fixes, item.header, 3, true) # LO returns before charging a partial block.
    if item.price <= 4095:
      # A sealed twelve-bit charge fits the ISA immediate field without materializing a scratch constant per visit.
      words.add(0xf100005f'u32 or (uint32(item.price) shl 10)) # CMP Xgas,#price, including zero.
      armRegionEdge(words, fixes, item.header, 3, true) # LO leaves the unpaid block entirely untouched.
      words.add(0xd1000042'u32 or (uint32(item.price) shl 10)) # SUB Xgas,Xgas,#price.
    else:
      # Wider prices keep the full unsigned 64-bit guard and subtraction with no truncation or sign extension.
      armImmediate(words, 1, item.price)
      words.add(0xeb01005f'u32) # CMP Xgas,Xprice.
      armRegionEdge(words, fixes, item.header, 3, true)
      words.add(0xcb010042'u32) # SUB Xgas,Xgas,Xprice after the unsigned sufficiency check.
    words.add(0xd1000063'u32 or (item.span shl 10)) # SUB Xremaining,Xremaining,#wholeSourceSpan.
    # One exact integer SIMD add replaces a context load/add/store; no FP arithmetic, flags or callee-saved state changes.
    let counter = uint32(index+16)
    words.add(0x5ef38400'u32 or (counter shl 5) or counter) # ADD Dcounter,Dcounter,D19 (integer scalar).
    for word in item.body.words: words.add(word)
    # Reuse the verified operand/compare prefix; omit its five scalar-return selection instructions.
    for position in 0..<item.body.terminal.len-5: words.add(item.body.terminal[position])
    let condition = (item.body.terminal[item.body.terminal.len-1] shr 12) and 15
    let following = if index+1 < count: blocks[index+1].header else: high(uint32)
    if item.no == following:
      # The false edge reaches the next guarded block by layout, retaining the original conditional transfer.
      armRegionEdge(words, fixes, item.yes, condition, false)
    elif item.yes == following:
      # ARM condition pairs differ in their low bit; invert only to make the true edge fall through its original guard.
      armRegionEdge(words, fixes, item.no, condition xor 1'u32, false)
    else:
      # Backedges and external destinations keep explicit transfers and the same guarded-return relocation.
      armRegionEdge(words, fixes, item.yes, condition, false)
      armRegionEdge(words, fixes, item.no, 16, false)
  for fix in fixes:
    # Every guarded return needs a stub, including guards whose header is also an internal branch destination.
    var internal = false
    if not fix.guard:
      for index in 0..<count:
        if blocks[index].header == fix.target: internal = true
    if internal: continue
    var known = false
    for target in exits:
      if target == fix.target: known = true
    if not known: exits.add(fix.target)
  var epilogueBranches: seq[int] = @[]
  for target in exits:
    # Preserve X0 as the borrowed register-file pointer until every resident value has been committed.
    exitLabels.add(words.len)
    words.add(0x52800001'u32 or ((target and 65535) shl 5))
    words.add(0x72a00001'u32 or ((target shr 16) shl 5))
    epilogueBranches.add(words.len)
    words.add(0)
  let epilogue = words.len
  for slot in 0..<13:
    if (written and (1'u32 shl slot)) != 0:
      words.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  words.add(0xf9000222'u32) # STR Xgas,[Xcontext].
  words.add(0xf9000623'u32) # STR Xremaining,[Xcontext,#8].
  # Publish invocation-local visits once on every guarded/external exit, preserving the existing five-word context ABI.
  words.add(0xfd000a30'u32)
  words.add(0xfd000e31'u32)
  words.add(0xfd001232'u32)
  words.add(0x2a0103e0'u32) # MOV W0,Wtarget after register/state publication.
  if words.len >= 1024: return @[]
  for at in epilogueBranches:
    # Stub branches are forward and bounded by the same 1,024-word image ceiling.
    words[at] = 0x14000000'u32 or uint32(epilogue-at)
  for fix in fixes:
    var destination = -1
    if not fix.guard:
      # Native successors return to their guarded block label without another Nim/C transition.
      for index in 0..<count:
        if blocks[index].header == fix.target: destination = labels[index]
    if destination < 0:
      for index in 0..<exits.len:
        if exits[index] == fix.target: destination = exitLabels[index]
    assert destination >= 0 and destination < words.len
    let relative = if destination >= fix.at: uint32(destination-fix.at)
      else: 0'u32-uint32(fix.at-destination)
    words[fix.at] = if fix.condition < 16:
        0x54000000'u32 or ((relative and 0x7ffff'u32) shl 5) or fix.condition
      else: 0x14000000'u32 or (relative and 0x3ffffff'u32)
  words

proc encodeArmRegisterRing*(ring: NativeRegisterRing): seq[uint32] =
  ## Reuse the resident regional emitter without retaining a legacy owner.
  var blocks = default(array[3, ArmRegionBlock])
  for index in 0..2:
    let item = ring.blocks[index]
    var body = newArmRegionBody()
    for operation in 0..<int(item.span)-1:
      let op = item.body[operation]
      emitArmOperation(body, op.opcode, op.slots, op.immediate)
    let branch = item.branch
    emitArmBranch(body, branch.opcode, branch.slots, branch.immediate, item.yes, item.no)
    blocks[index] = ArmRegionBlock(header: item.header, span: item.span,
      operations: item.span, yes: item.yes, no: item.no, price: item.price, body: move(body))
  result = armRegionWords(blocks, 3, true)
  if result.len != 0:
    # Direct shared publication expects a complete image including the leaf return.
    result.add(0xd65f03c0'u32)

proc publishArmRegion*(jit: ArmJit, blocks: array[3, ArmRegionBlock],
    count: range[2..3] = 3): bool =
  ## Preserve the legacy publisher and its original nonrotating entry.
  assert jit.region.status == 0
  var words = armRegionWords(blocks, count, false)
  if words.len == 0: return false
  # Shape/span/image negatives stay local under existing header probes; only owner-wide storage failure is sticky.
  jit.region.status = 1
  if not publishArmEntry(jit, blocks[0].header, 0, 0, words, true): return false
  for index in 0..<count:
    # The source owner retains only scalar proof facts and executable offsets, never invocation addresses.
    jit.region.headers[index] = blocks[index].header
    jit.region.spans[index] = blocks[index].span
    jit.region.prices[index] = blocks[index].price
    jit.region.operations[index] = blocks[index].operations
  if count == 2:
    # No fake source block is emitted or charged; the third context counter stays untouched and unpublished.
    jit.region.headers[2] = high(uint32)
    jit.region.spans[2] = 0
    jit.region.prices[2] = 0
    jit.region.operations[2] = 0
  jit.region.blockCount = uint32(count)
  jit.region.status = 2
  true

proc callArmRegion*(jit: ArmJit, registers: var RegisterFile, state: var array[5, uint64]): uint32 =
  ## Borrow registers and a fresh scalar context for one complete connected run; all pointers expire on return.
  assert jit.region.status == 2 and sizeof(RegisterFile) == 104
  let entry = jit.entries[int(jit.region.headers[0])]
  assert entry.code >= 2
  let available = state[1]
  let gas = state[0]
  assert state[2] == 0 and state[3] == 0 and state[4] == 0
  let destination = regionArena(jit.arena.handle, entry.code-2, addr registers, addr state)
  assert state[1] <= available and state[0] <= gas
  let consumed = available-state[1]
  var accounted = 0'u64
  inc jit.calls
  inc jit.branchCalls
  inc jit.headerCalls
  inc jit.region.calls
  for index in 0..<armRegionCount(jit):
    # Each block consumes at least as many source attempts as lowered operations; each individual product is bounded.
    let count = uint64(jit.region.operations[index])
    let span = uint64(jit.region.spans[index])
    let visits = state[index+2]
    assert count > 0 and span >= count
    # A uint32-sized visit count times the sealed uint32 span fits uint64; larger counts retain the quotient guard.
    if visits > uint64(high(uint32)):
      assert visits <= consumed div span
    let attempts = visits*span
    assert accounted <= consumed and attempts <= consumed-accounted
    accounted+=attempts
    jit.operations+=visits*count
    jit.region.blocks+=visits
  if jit.region.blockCount == 2: assert state[4] == 0
  assert accounted == consumed
  destination

func armRegionStatistics*(jit: ArmJit): array[2, uint64] =
  ## Distinguish connected calls from complete guarded blocks without labelling guest operations as CPU instructions.
  [jit.region.calls, jit.region.blocks]

func armDirtyLoopStatus*(jit: ArmJit): uint8 =
  jit.dirtyLoop.status

func armDirtyLoopChargeMatches*(jit: ArmJit, header, span: uint32, price: uint64): bool =
  jit.dirtyLoop.status == 2 and jit.dirtyLoop.header == header and
    jit.dirtyLoop.span == span and jit.dirtyLoop.price == price

proc armDirtyLoopObserve*(jit: ArmJit, header: uint32, backedge: bool): uint8 =
  ## Return 1 on a hot observed loop, 2 when the bounded probe should retire.
  if jit.dirtyLoop.status != 0 or int(header) >= jit.entries.len: return 2
  let entry = addr jit.entries[int(header)]
  if entry.code >= 2: return 2
  if entry.ending < 256: inc entry.ending
  if backedge and entry.operations < 64: inc entry.operations
  if entry.operations == 64: return 1
  if entry.ending == 256: return 2
  0

type ArmDirtyImage = object
  ## Cold image failure distinguishes a size decline from invalid source/fixups.
  words: seq[uint32]
  continuation: int
  sizeDeclined: bool

proc armDirtyLoopImage(item: ArmRegionBlock, baseSlot: range[0..12],
    displacement: uint32, word: ArmDirtyWordShape, residentMode, windowCache: bool): ArmDirtyImage =
  ## Emit one validated dirty body with either a standalone ABI or a shared resident-bank exit.
  assert not windowCache or residentMode
  var continuation = -1
  var words: seq[uint32] = @[]
  if residentMode:
    # X19..X28 belong to the caller's cycle frame; X4..X16 already hold guest live-ins.
    words = @[0xaa1403f1'u32, 0xaa1503e2'u32, 0xaa1603e3'u32,
        0xd2800001'u32, 0x9e670030'u32, 0x9e670031'u32,
        0x9e670032'u32, 0xd2800021'u32, 0x9e670033'u32]
  else:
    words = @[0xaa0103f1'u32, 0xf9400222'u32, 0xf9400623'u32,
        0xfd400a30'u32, 0xfd400e31'u32, 0xfd401232'u32, 0xd2800021'u32,
        0x9e670033'u32]
  var fixes: seq[ArmRegionFixup] = @[]
  var resident = item.body.reads or item.body.writes or (1'u32 shl int(baseSlot))
  var written = item.body.writes
  if word.enabled:
    # The optional word lowering has additional explicit inputs and writes.
    for slot in [word.source, word.shift, word.destination, word.base, word.bound]:
      resident = resident or (1'u32 shl int(slot))
    for slot in [word.destination, word.base, word.shift]:
      written = written or (1'u32 shl int(slot))
  if not residentMode:
    for slot in 0..<13:
      if (resident and (1'u32 shl slot)) != 0:
        words.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  let label = words.len
  let wordActive = word.enabled and item.yes == item.header and item.no != item.header and
      item.price <= high(uint64) div 4
  if wordActive:
    # Four original five-op blocks are accepted as one word only when all guards pass before mutation.
    let fourPrice = item.price*4
    var early: seq[ArmRegionFixup] = @[]
    var restore: seq[ArmRegionFixup] = @[]
    words.add(0xf100507f'u32) # CMP Xremaining,#20.
    early.add(ArmRegionFixup(at: words.len, condition: 3)); words.add(0) # B.LO byte loop.
    if fourPrice <= 4095:
      words.add(0xf100005f'u32 or (uint32(fourPrice) shl 10))
    else:
      armImmediate(words, 1, fourPrice)
      words.add(0xeb01005f'u32)
    early.add(ArmRegionFixup(at: words.len, condition: 3)); words.add(0)
    let sourceReg = uint32(word.source)+4
    let shiftReg = uint32(word.shift)+4
    let destReg = uint32(word.destination)+4
    let baseReg = uint32(word.base)+4
    let boundReg = uint32(word.bound)+4
    words.add(0xf240101f'u32 or (shiftReg shl 5)) # TST Xshift,#31.
    early.add(ArmRegionFixup(at: words.len, condition: 1)); words.add(0) # B.NE.
    words.add(0xb1001001'u32 or (baseReg shl 5)) # ADDS X1,Xbase,#4.
    early.add(ArmRegionFixup(at: words.len, condition: 2)); words.add(0) # B.HS on wrap.
    words.add(0xeb00003f'u32 or (boundReg shl 16)) # CMP X1,Xbound.
    early.add(ArmRegionFixup(at: words.len, condition: 8)); words.add(0) # B.HI.

    words.add(0x9e670054'u32) # Preserve gas, attempts and context while checking memory.
    words.add(0x9e670075'u32)
    words.add(0x9e670236'u32)
    words.add(0x2a0003e3'u32 or (baseReg shl 16)) # MOV W3,Wbase.
    words.add(0x52800002'u32 or ((displacement and 65535) shl 5))
    words.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
    words.add(0x0b020063'u32) # Modulo-2^32 effective address.
    words.add(0xf140407f'u32) # Protected prefix.
    restore.add(ArmRegionFixup(at: words.len, condition: 3)); words.add(0)
    words.add(0x12800082'u32) # MOVN W2,#4: last admitted four-byte start is 0xfffffffb.
    words.add(0xeb02007f'u32)
    restore.add(ArmRegionFixup(at: words.len, condition: 8)); words.add(0)
    words.add(0x7200047f'u32) # TST Waddress,#3; alignment keeps all four bytes in one page.
    restore.add(ArmRegionFixup(at: words.len, condition: 1)); words.add(0)
    var cacheMisses: seq[int] = @[]
    var cacheSuccess = -1
    if windowCache:
      # D3..D6 hold only this invocation's next aligned word, host pointer, page and
      # remaining selected-region capacity. D3 is zeroed once at macro entry.
      words.add(0x9e660061'u32) # FMOV X1,D3: next expected guest address.
      words.add(0xeb01007f'u32) # CMP X3,X1.
      cacheMisses.add(words.len); words.add(0) # B.NE to original descriptor check.
      words.add(0xd34cfc61'u32) # LSR X1,X3,#12: current page.
      words.add(0x9e6600a2'u32) # FMOV X2,D5: cached page.
      words.add(0xeb02003f'u32) # CMP X1,X2.
      cacheMisses.add(words.len); words.add(0)
      words.add(0x9e6600c2'u32) # FMOV X2,D6: original region capacity.
      words.add(0xf100105f'u32) # CMP X2,#4: next offset must still admit four bytes.
      cacheMisses.add(words.len); words.add(0) # B.LS to original descriptor check.
      words.add(0x9e660081'u32) # FMOV X1,D4: next private word pointer.
      words.add(0x9e670020'u32) # FMOV D0,X1: shared successful store input.
      words.add(0x91001061'u32) # ADD X1,X3,#4: next expected guest address.
      words.add(0x9e670023'u32) # FMOV D3,X1.
      words.add(0x9e660081'u32) # FMOV X1,D4.
      words.add(0x91001021'u32) # ADD X1,X1,#4: next private word pointer.
      words.add(0x9e670024'u32) # FMOV D4,X1.
      words.add(0xd1001042'u32) # SUB X2,X2,#4: remaining descriptor capacity.
      words.add(0x9e670046'u32) # FMOV D6,X2.
      cacheSuccess = words.len
      words.add(0) # B to shared success, after the original bitmap preflight.
    let cacheMiss = words.len
    for at in cacheMisses:
      let condition = if at == cacheMisses[^1]: 9'u32 else: 1'u32
      words[at] = 0x54000000'u32 or (uint32(cacheMiss-at) shl 5) or condition
    words.add(0xf9401631'u32) # Fresh descriptor pointer, context word 5.
    words.add(0xf100023f'u32)
    restore.add(ArmRegionFixup(at: words.len, condition: 0)); words.add(0)
    var admitted: seq[int] = @[]
    for selected in 0..<2:
      let region = 1-selected
      words.add(0xa9400a21'u32 or (uint32(region*3) shl 15))
      let absent = words.len
      words.add(0xb4000002'u32)
      words.add(0x91001042'u32) # Extent is len-7; adding four admits offsets <= len-4.
      words.add(0xcb010061'u32)
      words.add(0xeb02003f'u32)
      let outside = words.len
      words.add(0x54000002'u32)
      if windowCache:
        words.add(0xcb010042'u32) # SUB X2,X2,X1: positive remaining start capacity.
        words.add(0x9e670047'u32) # FMOV D7,X2; refresh only after the bitmap passes.
      words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10))
      words.add(0x8b010041'u32)
      words.add(0x9e670020'u32) # Keep borrowed word pointer in D0 through the bitmap check.
      admitted.add(words.len)
      words.add(0)
      let following = words.len
      words[absent] = words[absent] or (uint32(following-absent) shl 5)
      words[outside] = words[outside] or (uint32(following-outside) shl 5)
    restore.add(ArmRegionFixup(at: words.len, condition: 16)); words.add(0)
    let afterRegions = words.len
    for at in admitted: words[at] = 0x14000000'u32 or uint32(afterRegions-at)
    words.add(0x9e6602d1'u32)
    words.add(0xf9401a22'u32)
    words.add(0xd352fc61'u32)
    words.add(0xeb02003f'u32)
    restore.add(ArmRegionFixup(at: words.len, condition: 2)); words.add(0)
    words.add(0xf9401e22'u32)
    words.add(0xf100005f'u32)
    restore.add(ArmRegionFixup(at: words.len, condition: 0)); words.add(0)
    words.add(0x8b010c42'u32)
    words.add(0xd34cfc61'u32)
    words.add(0xd2800031'u32)
    words.add(0x9ac12231'u32)
    words.add(0xf9400041'u32)
    words.add(0xea11003f'u32)
    restore.add(ArmRegionFixup(at: words.len, condition: 0)); words.add(0) # First touch declines.
    if windowCache:
      # A successful full preflight alone publishes this call-local window. No clean bit
      # or owner metadata changes, and the selected pointer is borrowed only until return.
      words.add(0x9e660001'u32) # FMOV X1,D0: admitted private pointer.
      words.add(0x91001021'u32) # ADD X1,X1,#4.
      words.add(0x9e670024'u32) # FMOV D4,X1.
      words.add(0x91001061'u32) # ADD X1,X3,#4.
      words.add(0x9e670023'u32) # FMOV D3,X1.
      words.add(0xd34cfc61'u32) # LSR X1,X3,#12.
      words.add(0x9e670025'u32) # FMOV D5,X1.
      words.add(0x9e6600e2'u32) # FMOV X2,D7: selected region's positive capacity.
      words.add(0x9e670046'u32) # FMOV D6,X2.
      words[cacheSuccess] = 0x14000000'u32 or uint32(words.len-cacheSuccess)
    words.add(0x9e660282'u32)
    words.add(0x9e6602a3'u32)
    words.add(0x9e6602d1'u32)
    words.add(0x9e660001'u32) # FMOV X1,D0.
    words.add(0xb9000020'u32 or sourceReg) # STR Wsource,[X1], little-endian four-byte group.
    words.add(0x53187c00'u32 or (sourceReg shl 5) or destReg) # LSR Wdest,Wsource,#24.
    words.add(0x91001000'u32 or (baseReg shl 5) or baseReg)
    words.add(0x91008000'u32 or (shiftReg shl 5) or shiftReg)
    if fourPrice <= 4095:
      words.add(0xd1000042'u32 or (uint32(fourPrice) shl 10))
    else:
      armImmediate(words, 1, fourPrice)
      words.add(0xcb010042'u32)
    words.add(0xd1005063'u32) # Twenty original attempts.
    for group in 0..<4: words.add(0x5ef38610'u32) # Four completed blocks in D16.
    words.add(0x5ef38631'u32) # One native word group in D17.
    words.add(0xeb00001f'u32 or (boundReg shl 16) or (baseReg shl 5))
    let backedge = words.len
    words.add(0) # B.NE to the word preflight; final equality selects the real no arm.
    armRegionEdge(words, fixes, item.no, 16, false)
    let restoreLabel = words.len
    words.add(0x9e660282'u32)
    words.add(0x9e6602a3'u32)
    words.add(0x9e6602d1'u32)
    let restoreToByte = words.len
    words.add(0)
    let byteLabel = words.len
    for edge in early:
      words[edge.at] = 0x54000000'u32 or (uint32(byteLabel-edge.at) shl 5) or edge.condition
    for edge in restore:
      let relative = uint32(restoreLabel-edge.at)
      words[edge.at] = if edge.condition < 16:
          0x54000000'u32 or (relative shl 5) or edge.condition
        else: 0x14000000'u32 or relative
    words[backedge] = 0x54000001'u32 or ((0'u32-uint32(backedge-label) and 0x7ffff'u32) shl 5)
    words[restoreToByte] = 0x14000000'u32 or uint32(byteLabel-restoreToByte)
  words.add(0xf100007f'u32 or (item.span shl 10))
  armRegionEdge(words, fixes, item.header, 3, true) # Partial source budget returns before any current-block mutation.
  if item.price <= 4095:
    words.add(0xf100005f'u32 or (uint32(item.price) shl 10))
  else:
    armImmediate(words, 1, item.price)
    words.add(0xeb01005f'u32)
  armRegionEdge(words, fixes, item.header, 3, true) # Gas decline returns to canonical precedence.

  # The guard may reuse X2/X3/X17 only after preserving live gas, attempts and context in caller-saved SIMD lanes.
  let memoryFixStart = fixes.len
  words.add(0x9e670054'u32) # FMOV D20,X2.
  words.add(0x9e670075'u32) # FMOV D21,X3.
  words.add(0x9e670236'u32) # FMOV D22,X17.
  words.add(0x2a0003e3'u32 or ((uint32(baseSlot)+4) shl 16))
  words.add(0x52800002'u32 or ((displacement and 65535) shl 5))
  words.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
  words.add(0x0b020063'u32) # Modulo-2^32 effective address.
  words.add(0xf140407f'u32) # Protected prefix.
  armRegionEdge(words, fixes, item.header, 3, true)
  words.add(0x12800022'u32) # Last valid byte address is 0xfffffffe.
  words.add(0xeb02007f'u32)
  armRegionEdge(words, fixes, item.header, 8, true)
  words.add(0xf9401631'u32) # Fresh descriptor pointer, context word 5.
  words.add(0xf100023f'u32) # CMP X17,#0.
  armRegionEdge(words, fixes, item.header, 0, true)
  var admitted: seq[int] = @[]
  for selected in 0..<2:
    let region = 1-selected # RW before stack for the observed framebuffer, both checked equally.
    words.add(0xa9400a21'u32 or (uint32(region*3) shl 15))
    let absent = words.len
    words.add(0xb4000002'u32) # CBZ X2,next region.
    words.add(0x91001c42'u32) # Reconstruct full byte extent from conservative read descriptor.
    words.add(0xcb010061'u32)
    words.add(0xeb02003f'u32)
    let outside = words.len
    words.add(0x54000002'u32) # B.HS,next region.
    words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10))
    words.add(0x8b010041'u32)
    words.add(0x9e670020'u32) # FMOV D0,X1 keeps the admitted byte pointer through prefix arithmetic.
    admitted.add(words.len)
    words.add(0x14000000'u32)
    let following = words.len
    words[absent] = words[absent] or (uint32(following-absent) shl 5)
    words[outside] = words[outside] or (uint32(following-outside) shl 5)
  armRegionEdge(words, fixes, item.header, 16, true)
  let afterRegions = words.len
  for at in admitted: words[at] = words[at] or uint32(afterRegions-at)
  words.add(0x9e6602d1'u32) # FMOV X17,D22 restores context.
  words.add(0xf9401a22'u32) # Dirty word count, context word 6.
  words.add(0xd352fc61'u32) # Address >> 18 selects a 64-page word.
  words.add(0xeb02003f'u32)
  armRegionEdge(words, fixes, item.header, 2, true)
  words.add(0xf9401e22'u32) # Dirty bitmap pointer, context word 7.
  words.add(0xf100005f'u32) # CMP X2,#0.
  armRegionEdge(words, fixes, item.header, 0, true)
  words.add(0x8b010c42'u32)
  words.add(0xd34cfc61'u32)
  words.add(0xd2800031'u32)
  words.add(0x9ac12231'u32)
  words.add(0xf9400041'u32)
  words.add(0xea11003f'u32)
  armRegionEdge(words, fixes, item.header, 0, true) # Clean bit is always checked fallback.
  let memoryFixEnd = fixes.len
  words.add(0x9e660282'u32) # FMOV X2,D20.
  words.add(0x9e6602a3'u32) # FMOV X3,D21.
  words.add(0x9e6602d1'u32) # FMOV X17,D22.

  if item.price <= 4095:
    words.add(0xd1000042'u32 or (uint32(item.price) shl 10))
  else:
    armImmediate(words, 1, item.price)
    words.add(0xcb010042'u32)
  words.add(0xd1000063'u32 or (item.span shl 10))
  words.add(0x5ef38400'u32 or (16'u32 shl 5) or 16'u32)
  for word in item.body.words: words.add(word)
  for position in 0..<item.body.terminal.len-5: words.add(item.body.terminal[position])
  let condition = (item.body.terminal[item.body.terminal.len-1] shr 12) and 15
  armRegionEdge(words, fixes, item.yes, condition, false)
  armRegionEdge(words, fixes, item.no, 16, false)

  # A guard after spilling live state must restore it before taking the ordinary charged-header exit.
  let restoreLabel = words.len
  words.add(0x9e660282'u32)
  words.add(0x9e6602a3'u32)
  words.add(0x9e6602d1'u32)
  armRegionEdge(words, fixes, item.header, 16, true)

  var exits: seq[uint32] = @[]
  for fix in fixes:
    if not fix.guard and fix.target == item.header: continue
    if fix.target notin exits: exits.add(fix.target)
  var exitLabels: seq[int] = @[]
  var epilogueBranches: seq[int] = @[]
  for target in exits:
    exitLabels.add(words.len)
    words.add(0x52800001'u32 or ((target and 65535) shl 5))
    words.add(0x72a00001'u32 or ((target shr 16) shl 5))
    epilogueBranches.add(words.len)
    words.add(0)
  let epilogue = words.len
  if not residentMode:
    for slot in 0..<13:
      if (written and (1'u32 shl slot)) != 0:
        words.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
    words.add(0xf9000222'u32)
    words.add(0xf9000623'u32)
    words.add(0xfd000a30'u32)
    words.add(0xfd000e31'u32)
    words.add(0xfd001232'u32)
  words.add(0x2a0103e0'u32)
  if residentMode:
    continuation = words.len
    words.add(0) # The owning cycle patches one branch to its post-dirty accounting.
  if words.len >= 1024: return ArmDirtyImage(sizeDeclined: true)
  for at in epilogueBranches: words[at] = 0x14000000'u32 or uint32(epilogue-at)
  for fixIndex, fix in fixes:
    var destination = -1
    if fixIndex >= memoryFixStart and fixIndex < memoryFixEnd: destination = restoreLabel
    elif not fix.guard and fix.target == item.header: destination = label
    if destination < 0:
      for index in 0..<exits.len:
        if exits[index] == fix.target: destination = exitLabels[index]
    assert destination >= 0
    let relative = if destination >= fix.at: uint32(destination-fix.at)
      else: 0'u32-uint32(fix.at-destination)
    words[fix.at] = if fix.condition < 16:
        0x54000000'u32 or ((relative and 0x7ffff'u32) shl 5) or fix.condition
      else: 0x14000000'u32 or (relative and 0x3ffffff'u32)
  result = ArmDirtyImage(words: move(words), continuation: continuation)

proc publishArmDirtyLoop*(jit: ArmJit, item: ArmRegionBlock,
    baseSlot: range[0..12], displacement: uint32,
    word: ArmDirtyWordShape = default(ArmDirtyWordShape)): bool =
  ## Keep the memory-capable one-block loop separate from the established multi-block region.
  assert jit.dirtyLoop.status == 0
  if item.span != 5 or item.operations != 5 or item.span > 4095 or
      (item.yes != item.header and item.no != item.header): return false
  if item.body.terminal.len notin [6, 10]:
    if not item.body.compact or item.body.terminal.len < 7 or item.body.terminal.len > 9:
      return false
  let image = armDirtyLoopImage(item, baseSlot, displacement, word, false, false)
  if image.words.len == 0: return false
  var words = image.words
  jit.dirtyLoop.status = 1
  # The final arena slot remains reserved for the established multi-block region.
  if not publishArmEntry(jit, item.header, 0, 0, words): return false
  jit.dirtyLoop.header = item.header
  jit.dirtyLoop.span = item.span
  jit.dirtyLoop.price = item.price
  jit.dirtyLoop.operations = item.operations
  jit.dirtyLoop.code = jit.entries[int(item.header)].code
  jit.dirtyLoop.status = 2
  true

proc callArmDirtyLoopCore(jit: ArmJit, registers: var RegisterFile,
    descriptorPointer: pointer, dirtyWords: var seq[uint64],
    state: var array[8, uint64]): uint32 =
  ## All invocation pointers are borrowed only across this one native call.
  assert jit.dirtyLoop.status == 2 and sizeof(RegisterFile) == 104 and descriptorPointer != nil
  assert state[2] == 0 and state[3] == 0 and state[4] == 0
  let gas = state[0]
  let available = state[1]
  state[5] = cast[uint64](descriptorPointer)
  state[6] = uint64(dirtyWords.len)
  state[7] = 0
  if dirtyWords.len > 0: state[7] = cast[uint64](addr dirtyWords[0])
  let destination = regionArena(jit.arena.handle, jit.dirtyLoop.code-2, addr registers, addr state)
  assert state[0] <= gas and state[1] <= available
  let consumed = available-state[1]
  assert state[2] <= consumed div uint64(jit.dirtyLoop.span)
  assert state[2]*uint64(jit.dirtyLoop.span) == consumed
  assert state[3] <= state[2] div 4 and state[4] == 0
  inc jit.calls
  inc jit.branchCalls
  inc jit.headerCalls
  inc jit.dirtyLoop.calls
  jit.dirtyLoop.blocks+=state[2]
  jit.dirtyLoop.wordGroups+=state[3]
  jit.operations+=state[2]*uint64(jit.dirtyLoop.operations)
  if destination == jit.dirtyLoop.header: inc jit.dirtyLoop.declines
  destination

proc callArmDirtyLoop*(jit: ArmJit, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var array[8, uint64]): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmDirtyLoopCore(jit, registers, addr regions, dirtyWords, state)

proc callArmDirtyLoopContext*(jit: ArmJit, registers: var RegisterFile,
    context: var ArmReadContext, dirtyWords: var seq[uint64],
    state: var array[8, uint64]): uint32 =
  ## Borrow the complete 144-byte frame context for one full-mode native entry.
  assert jit != nil and jit.clippedReads and sizeof(context) == 144
  callArmDirtyLoopCore(jit, registers, addr context, dirtyWords, state)

func armDirtyLoopStatistics*(jit: ArmJit): array[3, uint64] =
  [jit.dirtyLoop.calls, jit.dirtyLoop.blocks, jit.dirtyLoop.declines]

func armDirtyWordGroups*(jit: ArmJit): uint64 =
  jit.dirtyLoop.wordGroups

type ArmMemoryCycleFixup = object ## Local labels only; no source or invocation address enters the image.
  at, target: int
  condition: uint32 # 0..15 is B.cond; 16 is unconditional B.

proc cycleEdge(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
    target: int, condition: uint32) =
  ## Defer a bounded intra-image branch until every source-shaped exit has a label.
  fixes.add(ArmMemoryCycleFixup(at: words.len, target: target, condition: condition))
  words.add(0)

proc cycleLoad(words: var seq[uint32], destination, base, byteOffset: uint32) =
  ## Load one aligned invocation word without making it an image-owned pointer.
  assert destination <= 30 and base <= 30 and byteOffset mod 8 == 0 and byteOffset <= 32760
  words.add(0xf9400000'u32 or ((byteOffset div 8) shl 10) or (base shl 5) or destination)

proc cycleStore(words: var seq[uint32], source, base, byteOffset: uint32) =
  ## Publish one scalar accounting word before returning to the checked adapter.
  assert source <= 31 and base <= 30 and byteOffset mod 8 == 0 and byteOffset <= 32760
  words.add(0xf9000000'u32 or ((byteOffset div 8) shl 10) or (base shl 5) or source)

proc cycleImmediate(words: var seq[uint32], destination: uint32, value: uint64) =
  ## Source headers may live in saved X28; initialize all four halfwords without X16 clobber.
  assert destination <= 30
  words.add(0xd2800000'u32 or (uint32(value and 65535) shl 5) or destination)
  for half in 1..3:
    words.add(0xf2800000'u32 or (uint32(half) shl 21) or
        (uint32((value shr (half*16)) and 65535) shl 5) or destination)

proc cycleMove(words: var seq[uint32], destination, source: uint32) =
  ## Copy an invocation pointer into a saved register or a child argument register.
  assert destination <= 30 and source <= 30
  words.add(0xaa0003e0'u32 or (source shl 16) or destination)

proc cycleCompare(words: var seq[uint32], left, right: uint32, word: bool = false) =
  ## Select a signed-width-independent equality test for captured scalar destinations.
  assert left <= 30 and right <= 30
  words.add((if word: 0x6b00001f'u32 else: 0xeb00001f'u32) or
      (right shl 16) or (left shl 5))

proc cycleCompareImmediate(words: var seq[uint32], left, value: uint32) =
  ## The narrow source span and zero-attempt guard fit A64's unsigned immediate field.
  assert left <= 30 and value <= 4095
  words.add(0xf100001f'u32 or (value shl 10) or (left shl 5))

proc cycleAddImmediate(words: var seq[uint32], destination, source, value: uint32,
    subtract: bool = false) =
  ## Arithmetic follows a complete unsigned gas/attempt guard or refunds an unstarted tail.
  assert destination <= 30 and source <= 30 and value <= 4095
  let base = if subtract: 0xd1000000'u32 else: 0x91000000'u32
  words.add(base or (value shl 10) or (source shl 5) or destination)

proc cycleAddRegister(words: var seq[uint32], destination, left, right: uint32,
    subtract: bool = false) =
  ## Wide sealed gas prices retain all sixty-four bits.
  assert destination <= 30 and left <= 30 and right <= 30
  let base = if subtract: 0xcb000000'u32 else: 0x8b000000'u32
  words.add(base or (right shl 16) or (left shl 5) or destination)

proc cyclePriceGuard(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
    price: uint64, refusal: int) =
  ## Gas insufficiency precedes partial-span fallback once zero attempts have been excluded.
  if price <= 4095:
    cycleCompareImmediate(words, 21, uint32(price))
  else:
    armImmediate(words, 1, price)
    cycleCompare(words, 21, 1)
  cycleEdge(words, fixes, refusal, 3) # LO.

proc cyclePriceChange(words: var seq[uint32], price: uint64, refund: bool = false) =
  ## The matching guard proved a subtraction safe; a failed read restores its unstarted price.
  if price <= 4095:
    cycleAddImmediate(words, 21, 21, uint32(price), not refund)
  else:
    armImmediate(words, 1, price)
    cycleAddRegister(words, 21, 21, 1, not refund)

proc cycleLinkChild(words: var seq[uint32], start: uint64, code: uint32): bool =
  ## BL's signed word displacement is computed against this exclusive owner's planned append offset.
  let at = uint64(words.len)
  if start > high(uint64)-at*4: return false
  let site = start+at*4
  if uint64(code) >= site or (code and 3) != 0 or (site and 3) != 0: return false
  let distance = (site-uint64(code)) div 4
  if distance == 0 or distance > 33554432'u64: return false
  words.add(0x94000000'u32 or ((0'u32-uint32(distance)) and 0x3ffffff'u32))
  true

func armMemoryCycleStatus*(jit: ArmJit): uint8 =
  ## Copy the cold, permanently refused or published state without exposing executable storage.
  jit.memoryCycle.status

func armResidentMemoryCycleActive*(jit: ArmJit): bool =
  ## Report whether the published cycle uses semantic inline dirty/read entries instead of child BLs.
  jit.memoryCycle.status == 2 and jit.memoryCycle.residentMode

func armMemoryCycleChargeMatches*(jit: ArmJit, index: range[0..1], header,
    span: uint32, price: uint64): bool =
  ## Every invocation checks sealed default-pricing coordinates before borrowing this driver.
  if jit.memoryCycle.status != 2: return false
  if index == 0:
    jit.memoryCycle.prefixHeader == header and jit.memoryCycle.prefixSpan == span and
      jit.memoryCycle.prefixPrice == price
  else:
    jit.memoryCycle.tailHeader == header and jit.memoryCycle.tailSpan == span and
      jit.memoryCycle.tailPrice == price

func armMemoryCycleStatistics*(jit: ArmJit): array[6, uint64] =
  ## Calls are outer C-to-arena entries; child calls are counted separately in lane five.
  [jit.memoryCycle.calls, jit.memoryCycle.prefixBlocks, jit.memoryCycle.tailBlocks,
      jit.memoryCycle.dirtyBlocks, jit.memoryCycle.wordGroups, jit.memoryCycle.dirtyCalls]

proc publishArmMemoryCycle*(jit: ArmJit, item: ArmMemoryCycleBlock): bool =
  ## Emit a complete inline prefix and BL only the existing same-owner dirty/read children.
  if item.tailRead.clippedReads and not jit.clippedReads: return false
  if jit.memoryCycle.status != 0: return false
  if jit.unavailable or jit.fragments >= 8191 or jit.codeBytes > 1048576:
    # This arena cannot regain executable capacity; avoid rescanning a valid prefix on later calls.
    jit.memoryCycle.status = 1
    return false
  if jit.dirtyLoop.status != 2: return false
  if item.prefixSpan == 0 or item.prefixSpan > 4095 or item.tailSpan == 0 or
      item.tailSpan > 4095 or item.prefixOperations == 0 or item.tailOperations == 0 or
      item.prefixOperations > item.prefixSpan or item.tailOperations > item.tailSpan or
      item.prefixBody.terminal.len != 0 or item.prefixBody.words.len == 0: return false
  if item.prefixHeader == item.dirtyHeader or item.prefixHeader == item.tailHeader or
      item.dirtyHeader == item.tailHeader or item.other == item.prefixHeader or
      item.other == item.dirtyHeader or item.other == item.tailHeader: return false
  if item.dirtyHeader != jit.dirtyLoop.header or item.tailEntry >= uint32(jit.entries.len) or
      item.prefixHeader >= uint32(jit.entries.len): return false
  let tail = jit.entries[int(item.tailEntry)]
  if tail.code < 2 or jit.dirtyLoop.code < 2: return false
  let dirtyCode = jit.dirtyLoop.code-2
  let tailCode = tail.code-2
  let planned = jit.codeBytes
  if uint64(dirtyCode) >= planned or uint64(tailCode) >= planned: return false

  # Source and children are now fixed for this owner. Any image/link failure is permanent.
  jit.memoryCycle.status = 1
  # Labels: start, after-dirty-count, tail, prefix-refusal, tail-refusal, read-refund, epilogue.
  var labels = default(array[7, int])
  var fixes: seq[ArmMemoryCycleFixup] = @[]
  var words: seq[uint32] = @[0xd10183ff'u32] # SUB SP,SP,#96; preserve alignment across BL.
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9000000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  cycleMove(words, 19, 0)
  cycleMove(words, 20, 1)
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  for register in 23'u32..27'u32: words.add(0xd2800000'u32 or register)
  cycleLoad(words, 28, 20, 104)

  labels[0] = words.len
  cycleCompareImmediate(words, 22, 0)
  cycleEdge(words, fixes, 3, 0) # A zero attempt budget wins before gas.
  cyclePriceGuard(words, fixes, item.prefixPrice, 3)
  cycleCompareImmediate(words, 22, item.prefixSpan)
  cycleEdge(words, fixes, 3, 3) # Partial block returns to the original reservation.
  cyclePriceChange(words, item.prefixPrice)
  cycleAddImmediate(words, 22, 22, item.prefixSpan, true)
  cycleMove(words, 0, 19)
  for instruction in armInstructions(item.prefixBody): words.add(instruction)
  cycleAddImmediate(words, 23, 23, 1)
  cycleImmediate(words, 28, uint64(item.prefixHeader))

  # Dirty child's first eight words are its unchanged ABI, including fresh memory pointers.
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  for index in 2'u32..4'u32: cycleStore(words, 31, 20, index*8)
  cycleMove(words, 0, 19)
  cycleMove(words, 1, 20)
  if not cycleLinkChild(words, planned, dirtyCode): return false
  cycleMove(words, 16, 0)
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  cycleLoad(words, 0, 20, 16)
  cycleAddRegister(words, 25, 25, 0)
  cycleCompareImmediate(words, 0, 0)
  cycleEdge(words, fixes, 1, 0)
  cycleImmediate(words, 28, uint64(item.dirtyHeader))
  labels[1] = words.len
  cycleLoad(words, 1, 20, 24)
  cycleAddRegister(words, 26, 26, 1)
  cycleAddImmediate(words, 27, 27, 1)
  armImmediate(words, 0, uint64(item.dirtyHeader))
  cycleCompare(words, 16, 0, true)
  cycleEdge(words, fixes, 6, 0) # A dirty guard returns the original unstarted header.

  labels[2] = words.len
  cycleCompareImmediate(words, 22, 0)
  cycleEdge(words, fixes, 4, 0)
  cyclePriceGuard(words, fixes, item.tailPrice, 4)
  cycleCompareImmediate(words, 22, item.tailSpan)
  cycleEdge(words, fixes, 4, 3)
  cyclePriceChange(words, item.tailPrice)
  cycleAddImmediate(words, 22, 22, item.tailSpan, true)
  cycleMove(words, 0, 19)
  cycleLoad(words, 1, 20, 40) # Fresh descriptor pointer, never a retained image address.
  if not cycleLinkChild(words, planned, tailCode): return false
  words.add(0x12800010'u32) # MOVN W16,#0: the read child's exact refusal sentinel.
  cycleCompare(words, 0, 16, true)
  cycleEdge(words, fixes, 5, 0)
  cycleAddImmediate(words, 24, 24, 1)
  cycleImmediate(words, 28, uint64(item.tailHeader))
  armImmediate(words, 16, uint64(item.prefixHeader))
  cycleCompare(words, 0, 16, true)
  cycleEdge(words, fixes, 0, 0) # Only the cached positive backedge repeats.
  cycleEdge(words, fixes, 6, 16) # The other sealed arm leaves the driver.

  labels[3] = words.len
  armImmediate(words, 0, uint64(item.prefixHeader))
  cycleEdge(words, fixes, 6, 16)
  labels[4] = words.len
  armImmediate(words, 0, uint64(item.tailHeader))
  cycleEdge(words, fixes, 6, 16)
  labels[5] = words.len
  cyclePriceChange(words, item.tailPrice, true)
  cycleAddImmediate(words, 22, 22, item.tailSpan)
  armImmediate(words, 0, uint64(item.tailHeader))
  cycleEdge(words, fixes, 6, 16)

  labels[6] = words.len
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  cycleStore(words, 23, 20, 64)
  cycleStore(words, 24, 20, 72)
  cycleStore(words, 25, 20, 80)
  cycleStore(words, 26, 20, 88)
  cycleStore(words, 27, 20, 96)
  cycleStore(words, 28, 20, 104)
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9400000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  words.add(0x910183ff'u32) # ADD SP,SP,#96.
  if words.len >= 1024: return false
  for fix in fixes:
    if fix.target < 0 or fix.target >= labels.len: return false
    let relative = int64(labels[fix.target])-int64(fix.at)
    if fix.condition < 16:
      if relative < -262144 or relative > 262143: return false
      words[fix.at] = 0x54000000'u32 or
          ((uint32(relative) and 0x7ffff'u32) shl 5) or fix.condition
    else:
      if relative < -33554432 or relative > 33554431: return false
      words[fix.at] = 0x14000000'u32 or (uint32(relative) and 0x3ffffff'u32)

  if not publishArmEntry(jit, item.prefixHeader, 0, 0, words, expectedStart = planned):
    return false
  jit.memoryCycle.prefixHeader = item.prefixHeader
  jit.memoryCycle.dirtyHeader = item.dirtyHeader
  jit.memoryCycle.tailHeader = item.tailHeader
  jit.memoryCycle.other = item.other
  jit.memoryCycle.prefixSpan = item.prefixSpan
  jit.memoryCycle.tailSpan = item.tailSpan
  jit.memoryCycle.prefixOperations = item.prefixOperations
  jit.memoryCycle.tailOperations = item.tailOperations
  jit.memoryCycle.prefixPrice = item.prefixPrice
  jit.memoryCycle.tailPrice = item.tailPrice
  jit.memoryCycle.status = 2
  true

func armResidentCycleSourceValid(jit: ArmJit, item: ArmMemoryCycleBlock): bool =
  ## Validate one exact source-shaped recipe independently of its outer entry ABI.
  if jit.dirtyLoop.status != 2: return false
  if item.prefixSpan == 0 or item.prefixSpan > 4095 or item.tailSpan == 0 or
      item.tailSpan > 4095 or item.prefixOperations == 0 or item.tailOperations == 0 or
      item.prefixOperations > item.prefixSpan or item.tailOperations > item.tailSpan or
      item.prefixBody.terminal.len != 0 or item.prefixBody.words.len == 0: return false
  if item.prefixHeader == item.dirtyHeader or item.prefixHeader == item.tailHeader or
      item.dirtyHeader == item.tailHeader or item.other == item.prefixHeader or
      item.other == item.dirtyHeader or item.other == item.tailHeader: return false
  if item.dirtyHeader != jit.dirtyLoop.header or item.tailEntry >= uint32(jit.entries.len) or
      item.prefixHeader >= uint32(jit.entries.len): return false
  let tail = jit.entries[int(item.tailEntry)]
  if tail.code < 2 or jit.dirtyLoop.code < 2: return false
  if item.dirty.header != item.dirtyHeader or item.dirty.span != jit.dirtyLoop.span or
      item.dirty.operations != jit.dirtyLoop.operations or item.dirty.price !=
          jit.dirtyLoop.price or
      item.dirty.body.words.len == 0 or
      not ((item.dirty.yes == item.dirtyHeader and item.dirty.no == item.tailHeader) or
      (item.dirty.no == item.dirtyHeader and item.dirty.yes == item.tailHeader)):
    return false
  if item.dirty.body.terminal.len notin [6, 10]:
    if not item.dirty.body.compact or item.dirty.body.terminal.len < 7 or
        item.dirty.body.terminal.len > 9: return false
  let requiredGuards = if item.tailRead.clippedReads: 1 else: 3
  if not item.tailRead.directFirst or item.tailRead.guards.len != requiredGuards or
      not item.tailRead.branchReady or item.tailRead.body.terminal.len == 0 or
      not ((item.tailRead.branchYes == item.prefixHeader and
      item.tailRead.branchNo == item.other) or
      (item.tailRead.branchNo == item.prefixHeader and
      item.tailRead.branchYes == item.other)): return false
  true

type ArmResidentCycleCore = object
  ## Cold code has no foreign entry/exit shell. Its end is an explicit continuation.
  ## X19/X20 borrow the register file/context; X0..X3/X17 and D0/D16..D22 are scratch.
  ## Guest X4..X16 and accounting X21..X28 remain live, with no register-file publication.
  words: seq[uint32]
  resident, written: uint32
  sizeDeclined: bool # Propagate only the dirty child's deterministic word-limit failure.

proc armResidentCycleCore(item: ArmMemoryCycleBlock,
    windowCache: bool = false): ArmResidentCycleCore =
  ## Render an admitted core; the caller initializes/exports its bank and accounting ABI.
  result = default(ArmResidentCycleCore)
  let dirtyImage = armDirtyLoopImage(item.dirty, item.dirtyBaseSlot,
      item.dirtyDisplacement, item.dirtyWord, true, windowCache)
  if dirtyImage.sizeDeclined:
    result.sizeDeclined = true
    return
  if dirtyImage.words.len == 0 or dirtyImage.continuation < 0: return
  let readImage = armReadImage(item.tailRead, item.tailHeader, true, true)
  if readImage.words.len == 0: return
  var resident = item.prefixBody.reads or item.prefixBody.writes or
      item.dirty.body.reads or item.dirty.body.writes or
      item.tailRead.body.reads or item.tailRead.body.writes or
      (1'u32 shl int(item.dirtyBaseSlot))
  var written = item.prefixBody.writes or item.dirty.body.writes or
      item.tailRead.body.writes
  if item.dirtyWord.enabled:
    for slot in [item.dirtyWord.source, item.dirtyWord.shift,
        item.dirtyWord.destination, item.dirtyWord.base, item.dirtyWord.bound]:
      resident = resident or (1'u32 shl int(slot))
    for slot in [item.dirtyWord.destination, item.dirtyWord.base,
        item.dirtyWord.shift]:
      written = written or (1'u32 shl int(slot))
  if ((resident or written) shr 13) != 0: return
  # All prospective guest stores have initialized root values even on a zero-work exit.
  # Labels: start, after-dirty-count, tail, prefix-refusal, tail-refusal, read-refund, epilogue.
  var labels = default(array[7, int])
  var fixes: seq[ArmMemoryCycleFixup] = @[]
  var words: seq[uint32] = @[]
  labels[0] = words.len
  cycleCompareImmediate(words, 22, 0)
  cycleEdge(words, fixes, 3, 0) # A zero attempt budget wins before gas.
  cyclePriceGuard(words, fixes, item.prefixPrice, 3)
  cycleCompareImmediate(words, 22, item.prefixSpan)
  cycleEdge(words, fixes, 3, 3) # Partial block returns to the original reservation.
  cyclePriceChange(words, item.prefixPrice)
  cycleAddImmediate(words, 22, 22, item.prefixSpan, true)
  for instruction in item.prefixBody.words: words.add(instruction)
  cycleAddImmediate(words, 23, 23, 1)
  cycleImmediate(words, 28, uint64(item.prefixHeader))

  # The shared dirty core consumes resident X4..X16 and returns with X2/X3 and D16/D17 live.
  let dirtyStart = words.len
  for instruction in dirtyImage.words: words.add(instruction)
  let afterDirty = words.len
  let dirtyJump = dirtyStart+dirtyImage.continuation
  words[dirtyJump] = 0x14000000'u32 or uint32(afterDirty-dirtyJump)
  cycleMove(words, 21, 2)
  cycleMove(words, 22, 3)
  words.add(0x9e660201'u32) # FMOV X1,D16: complete dirty blocks.
  cycleAddRegister(words, 25, 25, 1)
  cycleCompareImmediate(words, 1, 0)
  cycleEdge(words, fixes, 1, 0)
  cycleImmediate(words, 28, uint64(item.dirtyHeader))
  labels[1] = words.len
  words.add(0x9e660221'u32) # FMOV X1,D17: completed four-byte groups.
  cycleAddRegister(words, 26, 26, 1)
  cycleAddImmediate(words, 27, 27, 1) # One semantic dirty-child invocation.
  cycleImmediate(words, 1, uint64(item.dirtyHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 6, 0) # An unstarted dirty guard returns its header.

  labels[2] = words.len
  cycleCompareImmediate(words, 22, 0)
  cycleEdge(words, fixes, 4, 0)
  cyclePriceGuard(words, fixes, item.tailPrice, 4)
  cycleCompareImmediate(words, 22, item.tailSpan)
  cycleEdge(words, fixes, 4, 3)
  cyclePriceChange(words, item.tailPrice)
  cycleAddImmediate(words, 22, 22, item.tailSpan, true)
  cycleLoad(words, 1, 20, 40) # Borrow the fresh descriptor pointer for the direct read.
  let readStart = words.len
  for instruction in readImage.words: words.add(instruction)
  let afterRead = words.len
  let successJump = readStart+readImage.successAt
  words[successJump] = 0x14000000'u32 or uint32(afterRead-successJump)
  fixes.add(ArmMemoryCycleFixup(at: readStart+readImage.refusalAt,
      target: 5, condition: 16))
  cycleAddImmediate(words, 24, 24, 1)
  cycleImmediate(words, 28, uint64(item.tailHeader))
  armImmediate(words, 1, uint64(item.prefixHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 0, 0) # Only the cached positive backedge repeats.
  cycleEdge(words, fixes, 6, 16) # The other sealed arm leaves the driver.

  labels[3] = words.len
  armImmediate(words, 0, uint64(item.prefixHeader))
  cycleEdge(words, fixes, 6, 16)
  labels[4] = words.len
  armImmediate(words, 0, uint64(item.tailHeader))
  cycleEdge(words, fixes, 6, 16)
  labels[5] = words.len
  cyclePriceChange(words, item.tailPrice, true)
  cycleAddImmediate(words, 22, 22, item.tailSpan)
  armImmediate(words, 0, uint64(item.tailHeader))
  cycleEdge(words, fixes, 6, 16)

  labels[6] = words.len # Every exit reaches the caller-owned continuation.
  for fix in fixes:
    if fix.target < 0 or fix.target >= labels.len: return
    let relative = int64(labels[fix.target])-int64(fix.at)
    if fix.condition < 16:
      if relative < -262144 or relative > 262143: return
      words[fix.at] = 0x54000000'u32 or
          ((uint32(relative) and 0x7ffff'u32) shl 5) or fix.condition
    else:
      if relative < -33554432 or relative > 33554431: return
      words[fix.at] = 0x14000000'u32 or (uint32(relative) and 0x3ffffff'u32)

  result.resident = resident
  result.written = written
  result.words = move(words)

proc publishArmResidentMemoryCycle*(jit: ArmJit, item: ArmMemoryCycleBlock): bool =
  ## Compose already admitted dirty/direct-read cores into one resident guest-register bank.
  if item.tailRead.clippedReads and not jit.clippedReads: return false
  if jit.memoryCycle.status != 0: return false
  if jit.unavailable or jit.fragments >= 8191 or jit.codeBytes > 1048576:
    return false # The old linked driver may still fit when this larger image does not.
  if not armResidentCycleSourceValid(jit, item): return false
  let planned = jit.codeBytes
  let core = armResidentCycleCore(item)
  if core.words.len == 0: return false
  let resident = core.resident
  let written = core.written
  var words: seq[uint32] = @[0xd10183ff'u32] # SUB SP,SP,#96; preserve alignment across BL.
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9000000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  cycleMove(words, 19, 0)
  cycleMove(words, 20, 1)
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  for register in 23'u32..27'u32: words.add(0xd2800000'u32 or register)
  cycleLoad(words, 28, 20, 104)
  for slot in 0..<13:
    if (resident and (1'u32 shl slot)) != 0:
      cycleLoad(words, uint32(slot)+4, 19, uint32(slot*8))

  for instruction in core.words: words.add(instruction)
  for slot in 0..<13:
    if (written and (1'u32 shl slot)) != 0:
      cycleStore(words, uint32(slot)+4, 19, uint32(slot*8))
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  cycleStore(words, 23, 20, 64)
  cycleStore(words, 24, 20, 72)
  cycleStore(words, 25, 20, 80)
  cycleStore(words, 26, 20, 88)
  cycleStore(words, 27, 20, 96)
  cycleStore(words, 28, 20, 104)
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9400000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  words.add(0x910183ff'u32) # ADD SP,SP,#96.
  if words.len >= 1024 or uint64(words.len+1)*4 > 1048576-jit.codeBytes: return false

  if not publishArmEntry(jit, item.prefixHeader, 0, 0, words, expectedStart = planned):
    return false
  jit.memoryCycle.prefixHeader = item.prefixHeader
  jit.memoryCycle.dirtyHeader = item.dirtyHeader
  jit.memoryCycle.tailHeader = item.tailHeader
  jit.memoryCycle.other = item.other
  jit.memoryCycle.prefixSpan = item.prefixSpan
  jit.memoryCycle.tailSpan = item.tailSpan
  jit.memoryCycle.prefixOperations = item.prefixOperations
  jit.memoryCycle.tailOperations = item.tailOperations
  jit.memoryCycle.prefixPrice = item.prefixPrice
  jit.memoryCycle.tailPrice = item.tailPrice
  jit.memoryCycle.residentMode = true
  jit.memoryCycle.status = 2
  true

proc callArmMemoryCycleCore(jit: ArmJit, registers: var RegisterFile,
    descriptorPointer: pointer, dirtyWords: var seq[uint64],
    state: var array[14, uint64]): uint32 =
  ## One C-to-arena call; child-entry counters count semantic visits with or without physical BLs.
  assert jit.memoryCycle.status == 2 and sizeof(RegisterFile) == 104 and descriptorPointer != nil
  for index in 2..4: assert state[index] == 0
  for index in 8..12: assert state[index] == 0
  assert state[13] == uint64(high(uint32))
  let gas = state[0]
  let available = state[1]
  state[5] = cast[uint64](descriptorPointer)
  state[6] = uint64(dirtyWords.len)
  state[7] = 0
  if dirtyWords.len > 0: state[7] = cast[uint64](addr dirtyWords[0])
  let root = jit.entries[int(jit.memoryCycle.prefixHeader)]
  assert root.code >= 2
  result = regionArena(jit.arena.handle, root.code-2, addr registers, addr state)
  assert result == jit.memoryCycle.prefixHeader or result == jit.memoryCycle.dirtyHeader or
      result == jit.memoryCycle.tailHeader or result == jit.memoryCycle.other
  assert state[0] <= gas and state[1] <= available and state[4] == 0
  let consumed = available-state[1]
  let spent = gas-state[0]
  let prefix = state[8]
  let tail = state[9]
  let dirty = state[10]
  assert state[11] <= dirty div 4 and state[12] <= prefix and
      (state[12] == 0 or dirty >= state[12]-1)
  assert prefix <= consumed div uint64(jit.memoryCycle.prefixSpan)
  let prefixAttempts = prefix*uint64(jit.memoryCycle.prefixSpan)
  assert tail <= (consumed-prefixAttempts) div uint64(jit.memoryCycle.tailSpan)
  let tailAttempts = tail*uint64(jit.memoryCycle.tailSpan)
  assert dirty <= (consumed-prefixAttempts-tailAttempts) div uint64(jit.dirtyLoop.span)
  assert prefixAttempts+tailAttempts+dirty*uint64(jit.dirtyLoop.span) == consumed
  if jit.memoryCycle.prefixPrice > 0:
    assert prefix <= spent div jit.memoryCycle.prefixPrice
  let prefixGas = prefix*jit.memoryCycle.prefixPrice
  if jit.memoryCycle.tailPrice > 0:
    assert tail <= (spent-prefixGas) div jit.memoryCycle.tailPrice
  let tailGas = tail*jit.memoryCycle.tailPrice
  if jit.dirtyLoop.price > 0:
    assert dirty <= (spent-prefixGas-tailGas) div jit.dirtyLoop.price
  assert prefixGas+tailGas+dirty*jit.dirtyLoop.price == spent
  inc jit.calls # Only the outer C-to-arena entry counts as a native call.
  inc jit.branchCalls
  inc jit.headerCalls
  inc jit.memoryCycle.calls
  jit.memoryCycle.prefixBlocks+=prefix
  jit.memoryCycle.tailBlocks+=tail
  jit.memoryCycle.dirtyBlocks+=dirty
  jit.memoryCycle.wordGroups+=state[11]
  jit.memoryCycle.dirtyCalls+=state[12]
  jit.dirtyLoop.calls+=state[12] # Nested child invocations remain visible in its own counter.
  jit.dirtyLoop.blocks+=dirty
  jit.dirtyLoop.wordGroups+=state[11]
  if result == jit.memoryCycle.dirtyHeader: inc jit.dirtyLoop.declines
  jit.operations+=prefix*uint64(jit.memoryCycle.prefixOperations) +
      tail*uint64(jit.memoryCycle.tailOperations)+dirty*uint64(jit.dirtyLoop.operations)

proc callArmMemoryCycle*(jit: ArmJit, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var array[14, uint64]): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmMemoryCycleCore(jit, registers, addr regions, dirtyWords, state)

func armMacroStatus*(jit: ArmJit): uint8 =
  ## The separate macro owner is untried, retired, or completely published.
  jit.macroRoute.status

func armMacroResidentActive*(jit: ArmJit): bool =
  ## Distinguish the resident image from the linked image without changing either entry record.
  jit.macroRoute.status == 2 and jit.macroRoute.residentMode

func armMacroImageWords*(jit: ArmJit): uint32 =
  ## Expose the published image length for private qualification receipts.
  jit.macroRoute.imageWords

func armMacroChildRecord*(jit: ArmJit, offset: uint32): ArmMacroChildRecord =
  ## Copy an existing tuple without extending the entry map or compiling a node.
  if int(offset) >= jit.entries.len: return default(ArmMacroChildRecord)
  let entry = jit.entries[int(offset)]
  ArmMacroChildRecord(code: entry.code, operations: entry.operations,
    ending: entry.ending)

func armMacroCycleExit*(jit: ArmJit): uint32 =
  ## Only a published resident child exposes its sealed outside stream edge.
  assert jit.memoryCycle.status == 2 and jit.memoryCycle.residentMode
  jit.memoryCycle.other

func armMacroMatches*(jit: ArmJit, shape: ArmMacroShape): bool =
  ## A code-only cache is reusable only for the exact scalar source graph.
  jit.macroRoute.status == 2 and jit.macroRoute.shape == shape

func armMacroShape*(jit: ArmJit): ArmMacroShape =
  ## Copy published scalar coordinates without exposing mutable cache storage.
  assert jit.macroRoute.status == 2
  jit.macroRoute.shape

proc armMacroProbeReady*(jit: ArmJit): bool =
  ## Bound source observation to eight calls before Frame retires its handler.
  if jit.macroRoute.status != 0: return false
  if jit.macroRoute.probeVisits < 8: inc jit.macroRoute.probeVisits
  jit.macroRoute.probeVisits == 8

proc refuseArmMacro*(jit: ArmJit) =
  ## Shape refusal affects only the unpublished macro cache.
  if jit.macroRoute.status == 0: jit.macroRoute.status = 1

func armMacroStatistics*(jit: ArmJit): array[7, uint64] =
  ## Outer bridge and semantic child/control counts have distinct lanes.
  [jit.macroRoute.calls, jit.macroRoute.cycleChildCalls,
    jit.macroRoute.staticBlocks, jit.macroRoute.pureBlocks,
    jit.macroRoute.branchBlocks, jit.macroRoute.readBlocks,
    jit.macroRoute.readRefusals]

func armMacroShapeValid(jit: ArmJit, shape: ArmMacroShape): bool =
  ## Reject incompatible child records and edges before any code publication.
  if jit.memoryCycle.status != 2 or not jit.memoryCycle.residentMode or
      jit.dirtyLoop.status != 2 or jit.arena.handle == nil: return false
  let headers = [shape.cycleHeader, jit.memoryCycle.dirtyHeader,
    jit.memoryCycle.tailHeader, shape.staticHeader, shape.pureHeader,
    shape.branchHeader, shape.readHeader]
  for i in 0..<headers.len:
    if headers[i] >= 2147483646'u32: return false
    for j in 0..<i:
      if headers[i] == headers[j]: return false
  if shape.cycleHeader != jit.memoryCycle.prefixHeader or
      shape.cycleExit != jit.memoryCycle.other or
      shape.staticTarget != shape.pureHeader or
      shape.terminalTarget != shape.cycleHeader or
      shape.pureBody != shape.pureHeader+1 or
      shape.readBody != shape.readHeader+1: return false
  if not ((shape.pureYes == shape.branchHeader and
      shape.pureNo notin headers) or (shape.pureNo == shape.branchHeader and
      shape.pureYes notin headers)): return false
  if not ((shape.branchYes == shape.pureHeader and
      shape.branchNo == shape.readHeader) or
      (shape.branchNo == shape.pureHeader and
      shape.branchYes == shape.readHeader)): return false
  for span in [shape.staticSpan, shape.pureSpan, shape.branchSpan, shape.readSpan]:
    if span == 0 or span > 4095: return false
  let low = uint32(shape.branchImmediate and 0xffffffff'u64)
  let extended = if (low and 0x80000000'u32) != 0:
      uint64(low) or 0xffffffff00000000'u64 else: uint64(low)
  if shape.branchImmediate != extended: return false
  if shape.pureBody >= uint32(jit.entries.len) or
      shape.readBody >= uint32(jit.entries.len) or
      shape.cycleHeader >= uint32(jit.entries.len): return false
  let root = jit.entries[int(shape.cycleHeader)]
  let pure = jit.entries[int(shape.pureBody)]
  let read = jit.entries[int(shape.readBody)]
  if root.code < 2 or pure.code < 2 or read.code < 2 or
      pure.operations == 0 or read.operations == 0 or
      pure.operations > shape.pureSpan or read.operations >= shape.readSpan or
      pure.ending != shape.pureTerminal or read.ending != shape.readTerminal:
    return false
  if root.code-2 >= jit.codeBytes or pure.code-2 >= jit.codeBytes or
      read.code-2 >= jit.codeBytes: return false
  if shape.pureTerminal >= 2147483646'u32 or
      shape.readTerminal >= 2147483646'u32 or
      shape.pureYes >= 2147483646'u32 or
      shape.pureNo >= 2147483646'u32 or
      shape.branchYes >= 2147483646'u32 or
      shape.branchNo >= 2147483646'u32: return false
  true

proc armMacroCount(words: var seq[uint32], index: uint32) =
  ## Count one completed scalar block in invocation state without X16 scratch.
  cycleLoad(words, 1, 20, index*8)
  cycleAddImmediate(words, 1, 1, 1)
  cycleStore(words, 1, 20, index*8)

proc armCycleBudget(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
    span: uint32, price: uint64, refusal: int) =
  ## Attempt exhaustion wins over price; a partial block returns unmodified.
  cycleCompareImmediate(words, 22, 0)
  cycleEdge(words, fixes, refusal, 0)
  cyclePriceGuard(words, fixes, price, refusal)
  cycleCompareImmediate(words, 22, span)
  cycleEdge(words, fixes, refusal, 3)

proc armCycleDebit(words: var seq[uint32], span: uint32, price: uint64) =
  ## Debit only after the whole reservation and any unpaid preflight have succeeded.
  cyclePriceChange(words, price)
  cycleAddImmediate(words, 22, 22, span, true)

proc armMacroGuard(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
    span: uint32, price: uint64, refusal: int) =
  ## Legacy macro units reserve immediately after affordability checks.
  armCycleBudget(words, fixes, span, price, refusal)
  armCycleDebit(words, span, price)

proc armMacroPatch(words: var seq[uint32], fixes: seq[ArmMemoryCycleFixup],
    labels: openArray[int]): bool =
  ## Every local edge is instruction-relative and bounded before publication.
  for fix in fixes:
    if fix.target < 0 or fix.target >= labels.len: return false
    let relative = int64(labels[fix.target])-int64(fix.at)
    if fix.condition < 16:
      if relative < -262144 or relative > 262143: return false
      words[fix.at] = 0x54000000'u32 or
          ((uint32(relative) and 0x7ffff'u32) shl 5) or fix.condition
    else:
      if relative < -33554432 or relative > 33554431: return false
      words[fix.at] = 0x14000000'u32 or (uint32(relative) and 0x3ffffff'u32)
  true

when NativeReadCycleEnabled:
  const
    armStorePageMiss = 12
    armStorePageExtent = 13
    armStorePageCommit = 14
    armReadWindowReady = 15
    armReadWindowMiss = 16
    armReadWindowComplete = 17
    armStoreCommit = 18
    armTailLoaded = 19

  type ArmReadCycleLabels = array[armTailLoaded+1, int]
    ## Seven role edges, checked exits, and the Read, Store and Tail proof joins.

  proc appendArmCycleRead(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      span: ArmReadSpan, refusal: int) =
    ## Inline a true-length read bank with a caller-owned paid or unpaid refusal.
    cycleMove(words, 17, 20) # The shared read descriptors start at context byte zero.
    let start = words.len
    for instruction in span.body.words:
      words.add(instruction)
    for guard in span.guards:
      # The checked extent emitter uses an unconditional edge after all descriptors miss.
      assert not guard.conditional
      fixes.add(ArmMemoryCycleFixup(at: start+guard.at, target: refusal, condition: 16))

  proc emitArmEntryReadWindow(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      window: NativeReadWindow, done: int) =
    ## Prove all five qwords in descriptor zero before forming their borrowed pointer.
    ## Leave X0 zero on a miss so Read can use the original ordered search.
    words.add(0xaa1f03e0'u32) # MOV X0,XZR.
    let source = uint32(window.baseLane)+4
    if not armSmallIndirectAddress(words, source, window.first, false):
      armCompactImmediate(words, 2, uint64(window.first))
      words.add(0x0b020003'u32 or (source shl 5)) # ADD W3,Wsource,W2.
    armCompactImmediate(words, 2, uint64(high(uint32)-39'u32))
    cycleCompare(words, 3, 2)
    cycleEdge(words, fixes, done, 8) # HI: the window would wrap inside its 40 bytes.
    words.add(0xa9400a81'u32) # LDP X1,X2,[X20]: first descriptor's base and true length.
    words.add(0xf100a042'u32) # SUBS X2,X2,#40.
    cycleEdge(words, fixes, done, 3) # LO: a short extent cannot supply the whole window.
    cycleAddRegister(words, 1, 3, 1, subtract = true)
    cycleCompare(words, 1, 2)
    cycleEdge(words, fixes, done, 8) # HI: outside the first descriptor.
    cycleLoad(words, 2, 20, 16)
    cycleCompareImmediate(words, 2, 0)
    cycleEdge(words, fixes, done, 0)
    cycleAddRegister(words, 0, 2, 1)

  proc armCycleDirtyPage(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      refusal: int) =
    ## Test the absolute page bit for X3 without mutating the borrowed bitmap.
    words.add(0xd352fc61'u32) # LSR X1,X3,#18: bitmap word.
    cycleLoad(words, 2, 20, uint32(NativeCycleDirtyWordsOffset))
    cycleCompare(words, 1, 2)
    cycleEdge(words, fixes, refusal, 2) # HS: missing word.
    cycleLoad(words, 2, 20, uint32(NativeCycleDirtyOffset))
    cycleCompareImmediate(words, 2, 0)
    cycleEdge(words, fixes, refusal, 0)
    words.add(0x8b010c42'u32) # ADD X2,X2,X1,LSL #3.
    cycleLoad(words, 1, 2, 0)
    words.add(0xd34cfc62'u32) # LSR X2,X3,#12: page number.
    words.add(0xd2800020'u32) # MOV X0,#1.
    words.add(0x9ac22002'u32) # LSLV X2,X0,X2: hardware masks the bit index.
    words.add(0xea02003f'u32) # TST X1,X2.
    cycleEdge(words, fixes, refusal, 0)

  proc armCycleStorePageFill(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      labels: var ArmReadCycleLabels) =
    ## Use the accepted X25 pointer and X17 descriptor after the original dirty checks.
    ## The full page must belong to the same descriptor under stack-first selection.
    ## X27/X28 borrow that page only until this synchronous entry returns.
    ## X3 ended at effective+3. Publish the tag only after forming the page pointer.
    cycleAddImmediate(words, 3, 3, 3, true)
    words.add(0x92402c60'u32) # AND X0,X3,#4095.
    cycleCompareImmediate(words, 0, 4092)
    cycleEdge(words, fixes, armStorePageCommit, 8)
    words.add(0x12144c63'u32) # AND W3,W3,#0xfffff000.
    armCompactImmediate(words, 2, 0xfffff000'u64) # A hit at offset 4092 would admit 0xfffffffc.
    cycleCompare(words, 3, 2)
    cycleEdge(words, fixes, armStorePageCommit, 0) # The original upper bound is 0xfffffffb.
    # The stock low bound is page aligned. A threshold inside the page prevents a fill.
    cycleLoad(words, 1, 20, uint32(NativeCycleWritableOffset))
    cycleCompare(words, 3, 1)
    cycleEdge(words, fixes, armStorePageExtent, 2)
    words.add(0x91400462'u32) # ADD X2,X3,#1,LSL #12.
    cycleCompare(words, 2, 1)
    cycleEdge(words, fixes, armStorePageCommit, 8)
    labels[armStorePageExtent] = words.len
    words.add(0xa9400a21'u32) # LDP X1,X2,[X17].
    words.add(0xeb010061'u32) # SUBS X1,X3,X1.
    cycleEdge(words, fixes, armStorePageCommit, 3)
    words.add(0xf1400442'u32) # SUBS X2,X2,#1,LSL #12.
    cycleEdge(words, fixes, armStorePageCommit, 3)
    cycleCompare(words, 1, 2)
    cycleEdge(words, fixes, armStorePageCommit, 8)
    cycleAddRegister(words, 28, 25, 0, true)
    words.add(0xd34cfc7b'u32) # LSR X27,X3,#12.

  proc armCycleWordPreflight(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      labels: var ArmReadCycleLabels, word: NativeCycleWord, refusal: int, storePage: bool) =
    ## All four byte visits are proved before the store or the debit. X25 holds the writable pointer.
    ## A hit requires whole-word containment. A miss runs the original dirty checks so
    ## a first write returns unpaid to the checked Store, which owns dirty publication.
    let shift = uint32(word.shiftLane)+4
    let base = uint32(word.baseLane)+4
    let bound = uint32(word.boundLane)+4
    words.add(0xf240101f'u32 or (shift shl 5)) # TST Xshift,#31.
    cycleEdge(words, fixes, refusal, 1)
    words.add(0xb1001001'u32 or (base shl 5)) # ADDS X1,Xbase,#4.
    cycleEdge(words, fixes, refusal, 2) # HS: 64-bit wrap.
    cycleCompare(words, 1, bound)
    cycleEdge(words, fixes, refusal, 8) # HI: an earlier byte may hit the bound.
    let displacement = uint32(word.displacement and 0xffffffff'u64)
    if not armSmallIndirectAddress(words, base, displacement, false):
      # Materialize wide displacements before the modulo-32 effective address addition.
      armCompactImmediate(words, 2, uint64(displacement))
      words.add(0x0b020003'u32 or (base shl 5))
    if storePage:
      # X3 stays intact on either miss. X25 is the original commit's pointer.
      words.add(0xd34cfc61'u32) # LSR X1,X3,#12.
      cycleCompare(words, 1, 27)
      cycleEdge(words, fixes, armStorePageMiss, 1)
      words.add(0x92402c61'u32) # AND X1,X3,#4095.
      cycleCompareImmediate(words, 1, 4092)
      cycleEdge(words, fixes, armStorePageMiss, 8)
      cycleAddRegister(words, 25, 28, 1)
      cycleEdge(words, fixes, armStorePageCommit, 16)
      labels[armStorePageMiss] = words.len
    words.add(0xf140407f'u32) # CMP X3,#65536.
    cycleEdge(words, fixes, refusal, 3)
    armCompactImmediate(words, 2, uint64(high(uint32))-4'u64)
    cycleCompare(words, 3, 2)
    cycleEdge(words, fixes, refusal, 8)

    # Select stack when address >= its original base, even if its extent is empty.
    # A short or absent selected stack cannot fall through to RW.
    cycleAddImmediate(words, 17, 20, uint32(NativeCycleWritableOffset))
    cycleLoad(words, 1, 17, 0)
    cycleAddImmediate(words, 2, 17, 24)
    cycleCompare(words, 3, 1)
    words.add(0x9a822231'u32) # CSEL X17,X17,X2,HS.
    words.add(0xa9400a21'u32) # LDP X1,X2,[X17]: original base and true length.
    words.add(0xf1001042'u32) # SUBS X2,X2,#4.
    cycleEdge(words, fixes, refusal, 3)
    words.add(0xcb010061'u32) # SUB X1,X3,X1: below-base wraps beyond the length.
    cycleCompare(words, 1, 2)
    cycleEdge(words, fixes, refusal, 8)
    cycleLoad(words, 2, 17, 16)
    cycleCompareImmediate(words, 2, 0)
    cycleEdge(words, fixes, refusal, 0)
    cycleAddRegister(words, 25, 2, 1)
    armCycleDirtyPage(words, fixes, refusal)
    words.add(0xd34cfc61'u32) # LSR X1,X3,#12: first page.
    cycleAddImmediate(words, 3, 3, 3)
    words.add(0xd34cfc62'u32) # LSR X2,X3,#12: last page.
    cycleCompare(words, 1, 2)
    let samePage = words.len
    words.add(0)
    armCycleDirtyPage(words, fixes, refusal)
    words[samePage] = 0x54000000'u32 or (uint32(words.len-samePage) shl 5)
    if storePage:
      # A failed fill still commits the already-proved word at the original pointer.
      armCycleStorePageFill(words, fixes, labels)
      labels[armStorePageCommit] = words.len

  proc armCycleBranch(words: var seq[uint32], fixes: var seq[ArmMemoryCycleFixup],
      op: NativeOperation, target: int) =
    ## Emit the original predicate and branch directly to the certified true edge.
    var branch = newArmRegionBody()
    let condition = armBranchCompare(branch, op.opcode, op.slots.aIndex,
        op.slots.bIndex, op.immediate)
    for instruction in branch.terminal:
      words.add(instruction)
    cycleEdge(words, fixes, target, condition)

  proc armCycleStoreWord(words: var seq[uint32], value, byteReg, base, shift: uint32) =
    ## Commit a resolved four-visit Store and update its original guest lanes.
    words.add(0xb9000000'u32 or (25'u32 shl 5) or value) # STR Wvalue,[X25].
    words.add(0x53187c00'u32 or (value shl 5) or byteReg) # LSR Wbyte,Wvalue,#24.
    cycleAddImmediate(words, base, base, 4)
    cycleAddImmediate(words, shift, shift, 32)

  proc emitArmReadCycle(cycle: NativeReadCycle, storePage, allowWindow,
      allowStoreTail: bool): seq[uint32] =
    ## Render the copied seven-role cycle, using the already-paid first read and typed checked exits.
    ## The guest bank stays resident across roles. Read refusal restores its checkpoint before
    ## the common exit publishes the changed lanes.
    ##
    ## The invariant-base proof permits five ordered qword loads from the
    ## current bytes. ARM64 keeps their descriptor pointer in caller-saved D31.
    ## This leaf makes no calls and checkpoints guest writes in D18..D30. Read
    ## uses X0 for the pointer and X1..X3/X17 as scratch. D31 survives Store,
    ## which can reuse X0 and keeps its separate page proof in X27/X28.
    ## A miss selects the ordered read bank after the same paid checkpoint.
    ##
    ## Each entry resolves Tail's readable extent once.
    ## After the writable and dirty Store proof, ARM uses its exact gas and attempt ledgers to
    ## reserve the combined Store/Tail price and span. Pairing requires a mapped Tail, a Store
    ## successor at Tail and a nonoverflowing price. Otherwise the original per-role checks apply.
    ## The pair writes the Store before reading the live signed Tail word, including aliased bytes.
    const
      readCount = 22
      readOpcodes = [124'u8, 151, 130, 200, 129, 51, 151, 152, 130, 198, 132,
        198, 130, 197, 212, 151, 152, 130, 198, 130, 197, 212, 51, 200, 149]
      paidBody = 7
      readMiss = 8
      unpaid = 9
      commit = 10
      outside = 11
    result = @[]
    let sites = cycle.layout.sites
    let read = cycle.read.info
    let setup = cycle.read.continuationInfo
    if not cycle.read.complete or cycle.read.len != readCount+3 or
        read.header != sites[NativeCycleRole.Read].header or
        read.first != sites[NativeCycleRole.Read].first or read.last-read.first != 23 or
        setup.header != sites[NativeCycleRole.StoreSetup].header or
        setup.price != sites[NativeCycleRole.StoreSetup].price or
        cycle.tailLoad.opcode != 57 or
        cycle.tailStep.opcode != 131 or cycle.tailBranch.opcode != 173 or
        cycle.outer[0].opcode != 131 or cycle.outer[1].opcode != 149 or
        cycle.outer[2].opcode != 81 or cycle.gate.opcode != 88 or
        sites[NativeCycleRole.Store].price > high(uint64) div NativeCycleGroupVisits:
      return
    let storePrice = sites[NativeCycleRole.Store].price*NativeCycleGroupVisits
    let tailPrice = sites[NativeCycleRole.Tail].price
    let storeTail = storePage and allowStoreTail and tailPrice <= high(uint64)-storePrice
    let pairPrice = if storeTail: storePrice+tailPrice else: 0'u64
    let pairSpan = uint32(NativeCycleSpans[NativeCycleRole.Store]*NativeCycleGroupVisits +
      NativeCycleSpans[NativeCycleRole.Tail])
    let word = cycle.word
    let lanes = [word.valueLane, word.shiftLane, word.byteLane, word.baseLane, word.boundLane]
    for i in 0..<lanes.len:
      for j in i+1..<lanes.len:
        # A word projection needs the five distinct lanes of the checked proof.
        if lanes[i] == lanes[j]: return

    let window = if allowWindow: entryReadWindow(cycle) else: default(NativeReadWindow)
    let hasWindow = window.operations != 0
    var readBank = default(ArmReadSpan)
    readBank.body = newArmRegionBody()
    var windowBank = default(ArmReadSpan)
    windowBank.body = newArmRegionBody()
    var setupBank = newArmRegionBody()
    for index in 0..<cycle.read.len:
      let op = cycle.read.operation(index)
      # Refuse any profile outside the shared certificate's fixed opcode sequence.
      if op.opcode != readOpcodes[index]: return
      if index < readCount:
        if nativeReadOpcode(op.opcode):
          let opcode = int(op.opcode)
          assert opcode >= 124 and opcode <= 130
          emitArmCheckedRead(readBank, op.slots, uint32(op.immediate and 0xffffffff'u64),
              range[124..130](opcode), absolute = false)
          if hasWindow:
            if (window.operations and (1'u32 shl index)) != 0:
              let offset = uint32(op.immediate and 0xffffffff'u64)-window.first
              let destination = armWrite(windowBank.body, op.slots.aIndex)
              cycleLoad(windowBank.body.words, destination, 0, offset)
            else:
              emitArmCheckedRead(windowBank, op.slots, uint32(op.immediate and 0xffffffff'u64),
                  range[124..130](opcode), absolute = false)
        else:
          emitArmOperation(readBank.body, op.opcode, op.slots, op.immediate)
          if hasWindow:
            emitArmOperation(windowBank.body, op.opcode, op.slots, op.immediate)
      else:
        # The copied continuation executes only after its separate original header is paid.
        emitArmOperation(setupBank, op.opcode, op.slots, op.immediate)
    var tail = default(ArmReadSpan)
    armCompactImmediate(tail.body.words, 3, cycle.tailLoad.immediate and 0xffffffff'u64)
    emitArmCheckedReadAt(tail, 26, 129, pointerOnly = true)
    let tailSlot = uint32(cycle.tailLoad.slots.aIndex)
    var tailStep = newArmRegionBody()
    emitArmOperation(tailStep, cycle.tailStep.opcode, cycle.tailStep.slots,
        cycle.tailStep.immediate)
    var outer = newArmRegionBody()
    for index in 0..<2:
      let op = cycle.outer[index]
      emitArmOperation(outer, op.opcode, op.slots, op.immediate)

    let value = uint32(word.valueLane)+4
    let shift = uint32(word.shiftLane)+4
    let byteReg = uint32(word.byteLane)+4
    let base = uint32(word.baseLane)+4
    let bound = uint32(word.boundLane)+4
    let readWrites = readBank.body.writes
    assert not hasWindow or windowBank.body.writes == readWrites
    let written = readWrites or setupBank.writes or tailStep.writes or outer.writes or
        (1'u32 shl tailSlot) or (1'u32 shl int(word.shiftLane)) or
        (1'u32 shl int(word.byteLane)) or (1'u32 shl int(word.baseLane))
    var labels = default(ArmReadCycleLabels)
    var fixes: seq[ArmMemoryCycleFixup] = @[]
    var words = @[if storePage: 0xd10143ff'u32 else: 0xd10103ff'u32] # SUB SP,SP,#80 or #64.
    let pairs = if storePage: 5 else: 4
    for pair in 0..<pairs:
      # Save X19..X26 and the optional X27/X28 page proof. X18 is reserved.
      let first = uint32(19+pair*2)
      words.add(0xa9000000'u32 or (uint32(pair*2) shl 15) or
          ((first+1) shl 10) or (31'u32 shl 5) or first)
    cycleMove(words, 19, 0)
    cycleMove(words, 20, 1)
    if storePage:
      # No valid guest page can match the entry tag before the host page pointer is defined.
      words.add(0x1280001b'u32) # MOV W27,#0xffffffff.
    # Resolve only entry-local extent metadata. A miss stays zero until Tail.
    words.add(0xaa1f03fa'u32) # MOV X26,XZR. X26 is already saved in the frame.
    cycleMove(words, 17, 20)
    let tailProbeStart = words.len
    for instruction in tail.body.words:
      words.add(instruction)
    armReadPatchGuards(words, tail, tailProbeStart-1, words.len)
    cycleLoad(words, 21, 20, uint32(NativeCycleGasOffset))
    cycleLoad(words, 22, 20, uint32(NativeCycleRemainingOffset))
    cycleImmediate(words, 23, NativeCycleNoCompleted)
    for role in NativeCycleRole:
      # Receipts start empty for every entry, including an initial paid guard miss.
      cycleStore(words, 31, 20, uint32(NativeCycleVisitsOffset+ord(role)*8))
    for slot in 0..<13:
      # Initialize the entire resident bank before any guard can publish a dirty union.
      cycleLoad(words, uint32(slot)+4, 19, uint32(slot*8))
    if hasWindow:
      emitArmEntryReadWindow(words, fixes, window, armReadWindowReady)
      labels[armReadWindowReady] = words.len
      words.add(0x9e67001f'u32) # FMOV D31,X0.
    cycleEdge(words, fixes, paidBody, 16)

    for role in NativeCycleRole:
      labels[ord(role)] = words.len
      cycleImmediate(words, 24, uint64(sites[role].header))
      let groups = if role == NativeCycleRole.Store: NativeCycleGroupVisits else: 1'u64
      let span = uint32(NativeCycleSpans[role]*groups)
      let price = sites[role].price*groups
      armCycleBudget(words, fixes, span, price, unpaid)
      if role != NativeCycleRole.Store and role != NativeCycleRole.Tail:
        # Store and tail may decline preflight while still unpaid.
        armCycleDebit(words, span, price)
      case role
      of NativeCycleRole.Read:
        labels[paidBody] = words.len
        for slot in 0..<13:
          # These caller-saved lanes checkpoint only the current read's prospective writes.
          if (readWrites and (1'u32 shl slot)) != 0:
            words.add(0x9e670000'u32 or ((uint32(slot)+4) shl 5) or uint32(slot+18))
        if hasWindow:
          words.add(0x9e6603e0'u32) # FMOV X0,D31.
          cycleCompareImmediate(words, 0, 0)
          cycleEdge(words, fixes, armReadWindowMiss, 0)
          appendArmCycleRead(words, fixes, windowBank, readMiss)
          labels[armReadWindowComplete] = words.len
        else:
          appendArmCycleRead(words, fixes, readBank, readMiss)
      of NativeCycleRole.StoreSetup:
        for instruction in setupBank.words: words.add(instruction)
      of NativeCycleRole.Store:
        armCycleWordPreflight(words, fixes, labels, word, unpaid, storePage)
        if storeTail:
          # ARM keeps exact balances. Select the pair only after the Store proof and
          # before debit or publication. A short pair, backedge or absent Tail enters
          # the original Store commit, which can complete even when Tail must refuse.
          cycleAddImmediate(words, 0, base, 4) # The Store proof already excludes wrap.
          cycleCompare(words, 0, bound)
          cycleEdge(words, fixes, armStoreCommit, 1)
          cycleCompareImmediate(words, 26, 0)
          cycleEdge(words, fixes, armStoreCommit, 0)
          cyclePriceGuard(words, fixes, pairPrice, armStoreCommit)
          cycleCompareImmediate(words, 22, pairSpan)
          cycleEdge(words, fixes, armStoreCommit, 3)
          armCycleDebit(words, pairSpan, pairPrice)
          armCycleStoreWord(words, value, byteReg, base, shift)
          armMacroCount(words, uint32(NativeCycleVisitsOffset div 8+ord(role)))
          # Both roles are now guaranteed to complete. Load live bytes after the
          # Store, including when its writable word aliases the Tail pointer.
          words.add(0xb9800340'u32) # LDRSW X0,[X26].
          cycleEdge(words, fixes, armTailLoaded, 16)
          labels[armStoreCommit] = words.len
        armCycleDebit(words, span, price)
        # From the store through completion all instructions are non-faulting native bookkeeping.
        armCycleStoreWord(words, value, byteReg, base, shift)
      of NativeCycleRole.Tail:
        # A missing extent leaves this already-checked role unpaid.
        cycleCompareImmediate(words, 26, 0)
        cycleEdge(words, fixes, unpaid, 0)
        words.add(0xb9800340'u32) # LDRSW X0,[X26] reads bytes after all prior Stores.
        armCycleDebit(words, span, price)
        labels[armTailLoaded] = words.len
        cycleMove(words, tailSlot+4, 0)
        for instruction in tailStep.words: words.add(instruction)
      of NativeCycleRole.Jump, NativeCycleRole.Gate:
        discard # A terminal-only unit completes without a scalar body.
      of NativeCycleRole.Outer:
        for instruction in outer.words: words.add(instruction)

      armMacroCount(words, uint32(NativeCycleVisitsOffset div 8+ord(role)))
      words.add(0xd2800017'u32 or (uint32(ord(role)) shl 5)) # MOV X23,#role.
      case role
      of NativeCycleRole.Store:
        cycleCompare(words, base, bound)
        cycleEdge(words, fixes, ord(NativeCycleRole.Store), 1)
      of NativeCycleRole.Tail:
        armCycleBranch(words, fixes, cycle.tailBranch, ord(NativeCycleRole.StoreSetup))
      of NativeCycleRole.Outer:
        armCycleBranch(words, fixes, cycle.outer[2], outside)
      of NativeCycleRole.Gate:
        armCycleBranch(words, fixes, cycle.gate, ord(NativeCycleRole.Outer))
        cycleEdge(words, fixes, ord(NativeCycleRole.Read), 16)
      else:
        discard # The next emitted role is the original unconditional successor.

    labels[outside] = words.len
    cycleImmediate(words, 24, uint64(cycle.layout.outsideHeader))
    labels[unpaid] = words.len
    cycleMove(words, 0, 24)
    words.add(0xd2800001'u32) # paidRead = 0.
    cycleEdge(words, fixes, commit, 16)
    labels[readMiss] = words.len
    for slot in 0..<13:
      # Restore only this failed read. Earlier committed registers and stores survive.
      if (readWrites and (1'u32 shl slot)) != 0:
        words.add(0x9e660000'u32 or (uint32(slot+18) shl 5) or uint32(slot+4))
    armCompactImmediate(words, 0, uint64(read.header))
    words.add(0xd2800021'u32) # paidRead = 1. Retain the read's whole reservation.
    labels[commit] = words.len
    for slot in 0..<13:
      if (written and (1'u32 shl slot)) != 0:
        cycleStore(words, uint32(slot)+4, 19, uint32(slot*8))
    cycleStore(words, 21, 20, uint32(NativeCycleGasOffset))
    cycleStore(words, 22, 20, uint32(NativeCycleRemainingOffset))
    cycleStore(words, 23, 20, uint32(NativeCycleLastOffset))
    cycleStore(words, 1, 20, uint32(NativeCyclePaidReadOffset))
    for pair in 0..<pairs:
      # Restore every saved register before returning the checked destination in W0.
      let first = uint32(19+pair*2)
      words.add(0xa9400000'u32 or (uint32(pair*2) shl 15) or
          ((first+1) shl 10) or (31'u32 shl 5) or first)
    words.add(if storePage: 0x910143ff'u32 else: 0x910103ff'u32) # ADD SP,SP,#80 or #64.
    words.add(0xd65f03c0'u32) # RET.
    if hasWindow:
      # Share the checkpoint, paid refusal and Read completion accounting.
      labels[armReadWindowMiss] = words.len
      appendArmCycleRead(words, fixes, readBank, readMiss)
      cycleEdge(words, fixes, armReadWindowComplete, 16)
    if words.len <= NativeImageByteLimit div 4 and armMacroPatch(words, fixes, labels):
      result = move(words)

  proc armReadCycleInstructions*(cycle: NativeReadCycle): seq[uint32] =
    ## Prefer the Read window and Store/Tail pair with the entry-local Store page proof.
    ## The 4,096-byte ceiling still admits the original Read window or ordered probes.
    result = emitArmReadCycle(cycle, storePage = true, allowWindow = true, allowStoreTail = true)
    if result.len == 0:
      # Keep the existing Read-window image if the pair exceeds the byte ceiling.
      result = emitArmReadCycle(cycle, storePage = true, allowWindow = true, allowStoreTail = false)
    if result.len == 0:
      # The ordered Read body may leave room for the pair when the window did not fit.
      result = emitArmReadCycle(cycle, storePage = true, allowWindow = false, allowStoreTail = true)
    if result.len == 0:
      result = emitArmReadCycle(cycle, storePage = true, allowWindow = false,
          allowStoreTail = false)
    if result.len == 0:
      # Preserve admission of an image whose original probes fit the ceiling.
      result = emitArmReadCycle(cycle, storePage = false, allowWindow = false,
          allowStoreTail = false)

func armWindowInstructionSafe(instruction: uint32): bool =
  ## Admit only present integer emitter families and the dirty byte body's exact
  ## FMOV X1,D0. SIMD/FP load-store, SVE/SME, calls and unknown forms decline.
  if instruction == 0x9e660001'u32: return true
  let family = (instruction shr 25) and 15'u32
  if not (family == 4 or family == 5 or family == 8 or family == 9 or
      family == 10 or family == 11 or family == 12 or family == 13): return false
  if (instruction and 0xfc000000'u32) == 0x94000000'u32: return false # BL immediate.
  if (instruction and 0xfe000000'u32) == 0xd6000000'u32: return false # BR/BLR/RET family.
  true

func armWindowScratchSafe(body: ArmBlock): bool =
  ## D3..D7 remain private only if every source-supplied word is in the
  ## audited integer emitter set or the one explicit D0 read.
  for instruction in body.words:
    if not armWindowInstructionSafe(instruction): return false
  for instruction in body.terminal:
    if not armWindowInstructionSafe(instruction): return false
  true

type ArmResidentMacroImage = object
  ## Pure cold rendering owns its words; only size refusal permits a second render.
  words: seq[uint32]
  sizeDeclined: bool

proc armResidentMacroImage(shape: ArmMacroShape, cycle: ArmMemoryCycleBlock,
    pure: ArmBlock, read: ArmReadSpan, branchBody: ArmBlock, cacheWindow: bool,
    remainingBytes: uint64): ArmResidentMacroImage =
  ## Render and patch one complete bounded image without touching its executable owner.
  ## A late Read guard restores only that Read's written guest lanes from D18–D30,
  ## refunds its full gas price and attempt span, and returns to the original Read
  ## header. Earlier committed stores and their receipts survive. The checkpoint
  ## lives only through the Read, which does not use those SIMD lanes.
  result = default(ArmResidentMacroImage)
  let readImage = armMacroReadImage(read)
  if readImage.words.len == 0: return
  let core = armResidentCycleCore(cycle, cacheWindow)
  if core.sizeDeclined:
    result.sizeDeclined = true
    return
  if core.words.len == 0: return
  let resident = core.resident or pure.reads or pure.writes or
      branchBody.reads or branchBody.writes or read.body.reads or read.body.writes
  let written = core.written or pure.writes or branchBody.writes or read.body.writes
  if ((resident or written) shr 13) != 0: return

  # Labels: cycle, static, pure, branch88, read, read-success, four unstarted
  # controls, read rollback, and the common final publication/return.
  var labels = default(array[12, int])
  var fixes: seq[ArmMemoryCycleFixup] = @[]
  var words: seq[uint32] = @[0xd10183ff'u32] # SUB SP,SP,#96.
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9000000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  cycleMove(words, 19, 0)
  cycleMove(words, 20, 1)
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  for register in 23'u32..27'u32: words.add(0xd2800000'u32 or register)
  cycleLoad(words, 28, 20, 192) # Global last header starts at its caller's sentinel.
  for slot in 0..<13:
    if (resident and (1'u32 shl slot)) != 0:
      cycleLoad(words, uint32(slot)+4, 19, uint32(slot*8))

  if cacheWindow:
    words.add(0xd2800001'u32) # MOV X1,#0: an effective guest address cannot match invalid cache.
    words.add(0x9e670023'u32) # FMOV D3,X1: invalidate only at this outer native entry.

  labels[0] = words.len
  armMacroCount(words, 19) # One semantic cycle child, with no physical BL.
  for index in 2'u32..4'u32: cycleStore(words, 31, 20, index*8)
  for index in 8'u32..12'u32: cycleStore(words, 31, 20, index*8)
  cycleImmediate(words, 1, uint64(high(uint32)))
  cycleStore(words, 1, 20, 104) # Each semantic child starts at its own sentinel.
  for index in 0'u32..4'u32:
    words.add(0x9e670000'u32 or ((23+index) shl 5) or (23+index))
      # D23..D27 retain the child's starting counters across the shared core.
  for instruction in core.words: words.add(instruction)
  for index in 0'u32..4'u32:
    words.add(0x9e660000'u32 or ((23+index) shl 5) or 1'u32)
    cycleAddRegister(words, 2, 23+index, 1, true)
    cycleStore(words, 2, 20, (8+index)*8) # Publish this child invocation's own ledger.
  words.add(0x9e6602e1'u32) # FMOV X1,D23; reuse the saved prefix count without borrowing X29.
  cycleCompare(words, 23, 1)
  cycleLoad(words, 2, 20, 104) # The child sentinel survives a zero-progress cycle.
  words.add(0x9a800000'u32 or (2'u32 shl 16) or (1'u32 shl 12) or
      (28'u32 shl 5) or 2'u32) # CSEL X2,X28,X2,NE.
  cycleStore(words, 2, 20, 104)
  cycleImmediate(words, 1, uint64(shape.staticHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 1, 0)
  cycleEdge(words, fixes, 11, 16)

  labels[1] = words.len
  armMacroGuard(words, fixes, shape.staticSpan, shape.staticPrice, 6)
  armMacroCount(words, 20)
  cycleImmediate(words, 28, uint64(shape.staticHeader))

  labels[2] = words.len
  armMacroGuard(words, fixes, shape.pureSpan, shape.purePrice, 7)
  for instruction in pure.words: words.add(instruction)
  for instruction in pure.terminal: words.add(instruction)
  armMacroCount(words, 21)
  cycleImmediate(words, 28, uint64(shape.pureHeader))
  cycleImmediate(words, 1, uint64(shape.branchHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 3, 0)
  cycleEdge(words, fixes, 11, 16) # The genuine rare pure arm exits to checked C.

  labels[3] = words.len
  armMacroGuard(words, fixes, shape.branchSpan, shape.branchPrice, 8)
  for instruction in branchBody.words: words.add(instruction)
  for instruction in branchBody.terminal: words.add(instruction)
  armMacroCount(words, 22)
  cycleImmediate(words, 28, uint64(shape.branchHeader))
  cycleImmediate(words, 1, uint64(shape.pureHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 2, 0)
  cycleEdge(words, fixes, 4, 16)

  labels[4] = words.len
  armMacroGuard(words, fixes, shape.readSpan, shape.readPrice, 9)
  for slot in 0..<13:
    if (read.body.writes and (1'u32 shl slot)) != 0:
      words.add(0x9e670000'u32 or ((uint32(slot)+4) shl 5) or uint32(slot+18))
  cycleLoad(words, 1, 20, 40) # The fresh invocation's descriptors, never a cached address.
  let readStart = words.len
  for instruction in readImage.words: words.add(instruction)
  fixes.add(ArmMemoryCycleFixup(at: readStart+readImage.successAt,
      target: 5, condition: 16))
  fixes.add(ArmMemoryCycleFixup(at: readStart+readImage.refusalAt,
      target: 10, condition: 16))

  labels[5] = words.len
  armMacroCount(words, 23)
  cycleImmediate(words, 28, uint64(shape.readHeader))
  cycleEdge(words, fixes, 0, 16) # Cached opcode1 returns to the resident cycle guard.

  labels[6] = words.len
  cycleImmediate(words, 0, uint64(shape.staticHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[7] = words.len
  cycleImmediate(words, 0, uint64(shape.pureHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[8] = words.len
  cycleImmediate(words, 0, uint64(shape.branchHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[9] = words.len
  cycleImmediate(words, 0, uint64(shape.readHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[10] = words.len
  for slot in 0..<13:
    if (read.body.writes and (1'u32 shl slot)) != 0:
      words.add(0x9e660000'u32 or (uint32(slot+18) shl 5) or uint32(slot+4))
  cyclePriceChange(words, shape.readPrice, true)
  cycleAddImmediate(words, 22, 22, shape.readSpan)
  armMacroCount(words, 25)
  cycleImmediate(words, 0, uint64(shape.readHeader))
  cycleEdge(words, fixes, 11, 16)

  labels[11] = words.len
  for slot in 0..<13:
    if (written and (1'u32 shl slot)) != 0:
      cycleStore(words, uint32(slot)+4, 19, uint32(slot*8))
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  for index in 0'u32..4'u32: cycleStore(words, 23+index, 20, (14+index)*8)
  cycleStore(words, 28, 20, 192)
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9400000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  words.add(0x910183ff'u32) # ADD SP,SP,#96; arena appends RET.
  if words.len >= 1024 or uint64(words.len+1)*4 > remainingBytes:
    # Only a deterministic final footprint refusal can select the smaller resident image.
    result.sizeDeclined = true
    return
  if words.len == 0 or not armMacroPatch(words, fixes, labels): return
  words.add(0xd65f03c0'u32)
  result.words = move(words)

proc publishArmResidentMacro*(jit: ArmJit, shape: ArmMacroShape,
    cycle: ArmMemoryCycleBlock, pure: ArmBlock, read: ArmReadSpan): bool =
  ## Compose typed cycle, pure and multi-read bodies behind the existing 26-word macro ABI.
  ## This direct publisher checks the copied shape against the owner's installed children.
  ## The image must fit 1,024 words including RET and the remaining space under the
  ## 1 MiB arena limit. An owner with 8,192 fragments cannot append another image.
  ## Resident refusal leaves the children available for a linked macro.
  if (cycle.tailRead.clippedReads or read.clippedReads) and not jit.clippedReads:
    return false
  when defined(pvmArmMacroResidentRefuse):
    return false # A resident-only refusal leaves the linked publication available.
  if jit.macroRoute.status != 0 or jit.unavailable or jit.fragments >= 8192 or
      jit.codeBytes > 1048576 or not armMacroShapeValid(jit, shape) or
      not armResidentCycleSourceValid(jit, cycle): return false
  if cycle.prefixHeader != shape.cycleHeader or cycle.other != shape.staticHeader or
      cycle.dirtyHeader != jit.memoryCycle.dirtyHeader or
      cycle.tailHeader != jit.memoryCycle.tailHeader or
      cycle.prefixSpan != jit.memoryCycle.prefixSpan or
      cycle.tailSpan != jit.memoryCycle.tailSpan or
      cycle.prefixPrice != jit.memoryCycle.prefixPrice or
      cycle.tailPrice != jit.memoryCycle.tailPrice or
      cycle.prefixOperations != jit.memoryCycle.prefixOperations or
      cycle.tailOperations != jit.memoryCycle.tailOperations or
      pure.words.len == 0 or pure.terminal.len == 0 or
      read.body.words.len == 0 or read.body.terminal.len != 0: return false
  # Frame-built full contexts bound every raw writable descriptor to one fixed
  # private allocation. Legacy raw witness contexts retain the unchanged macro.
  let windowCache = jit.clippedReads and cycle.dirtyWord.enabled and
      cycle.dirty.yes == cycle.dirty.header and cycle.dirty.no != cycle.dirty.header and
      cycle.dirty.price <= high(uint64) div 4
  var branchBody = default(ArmBlock)
  emitArmBranchSlots(branchBody, 88'u8, shape.branchSlot, 0,
      shape.branchImmediate, shape.branchYes, shape.branchNo)
  let windowScratchSafe = armWindowScratchSafe(cycle.prefixBody) and
      armWindowScratchSafe(cycle.dirty.body) and
      armWindowScratchSafe(cycle.tailRead.body) and
      armWindowScratchSafe(pure) and armWindowScratchSafe(read.body) and
      armWindowScratchSafe(branchBody)
  let useWindowCache = windowCache and windowScratchSafe
  let root = jit.entries[int(shape.cycleHeader)]
  let pureChild = jit.entries[int(shape.pureBody)]
  let readChild = jit.entries[int(shape.readBody)]
  let planned = jit.codeBytes
  let remainingBytes = 1048576-jit.codeBytes
  var image = armResidentMacroImage(shape, cycle, pure, read, branchBody,
      useWindowCache, remainingBytes)
  if useWindowCache and image.sizeDeclined:
    # Re-render once before publication; preserve uncached resident admission at either capacity limit.
    image = armResidentMacroImage(shape, cycle, pure, read, branchBody, false, remainingBytes)
  if image.words.len == 0: return false
  var words = move(image.words)
  when defined(pvmArmMacroPublishRefuse):
    return false # The existing macro-append refusal applies to both image kinds.
  let address = publishArena(jit.arena.handle, addr words[0], uint32(words.len))
  if address < 0: return false
  inc jit.fragments
  jit.codeBytes+=uint64(words.len)*4
  if uint64(address) != planned: return false
  jit.macroRoute.code = uint32(address)+2
  jit.macroRoute.imageWords = uint32(words.len)
  jit.macroRoute.shape = shape
  jit.macroRoute.cycleCode = root.code
  jit.macroRoute.pureCode = pureChild.code
  jit.macroRoute.readCode = readChild.code
  jit.macroRoute.pureOperations = pureChild.operations
  jit.macroRoute.readOperations = readChild.operations
  jit.macroRoute.residentMode = true
  jit.macroRoute.status = 2
  true

proc publishArmMacro*(jit: ArmJit, shape: ArmMacroShape): bool =
  ## Link the three existing same-owner children and source-derived scalar controls.
  ## The single macro record needs a new fragment under the 8,192-fragment limit,
  ## at most 1,024 words including RET in the remaining 1 MiB arena, and reachable
  ## same-arena children. A failed append leaves the children intact.
  if jit.macroRoute.status != 0: return false
  if jit.unavailable or jit.fragments >= 8192 or jit.codeBytes > 1048576 or
      not armMacroShapeValid(jit, shape):
    jit.macroRoute.status = 1
    return false
  let root = jit.entries[int(shape.cycleHeader)]
  let pure = jit.entries[int(shape.pureBody)]
  let read = jit.entries[int(shape.readBody)]
  let planned = jit.codeBytes
  jit.macroRoute.status = 1

  # Labels: cycle, static, pure, branch88, read, spare, four unstarted exits,
  # late-read refund, and the common epilogue. Each child remains immutable.
  var labels = default(array[12, int])
  var fixes: seq[ArmMemoryCycleFixup] = @[]
  var words: seq[uint32] = @[0xd10183ff'u32] # SUB SP,SP,#96.
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9000000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  cycleMove(words, 19, 0)
  cycleMove(words, 20, 1)
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  cycleLoad(words, 23, 20, 192) # Global last-completed header, distinct from child word13.

  labels[0] = words.len
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  for index in 2'u32..4'u32: cycleStore(words, 31, 20, index*8)
  for index in 8'u32..12'u32: cycleStore(words, 31, 20, index*8)
  cycleImmediate(words, 1, uint64(high(uint32)))
  cycleStore(words, 1, 20, 104) # Child word13 always starts at the sentinel.
  cycleMove(words, 0, 19)
  cycleMove(words, 1, 20)
  if not cycleLinkChild(words, planned, root.code-2): return false
  cycleLoad(words, 21, 20, 0)
  cycleLoad(words, 22, 20, 8)
  for index in 0'u32..4'u32:
    cycleLoad(words, 1, 20, (8+index)*8)
    cycleLoad(words, 2, 20, (14+index)*8)
    cycleAddRegister(words, 2, 2, 1)
    cycleStore(words, 2, 20, (14+index)*8)
  armMacroCount(words, 19)
  cycleLoad(words, 1, 20, 104)
  cycleImmediate(words, 2, uint64(high(uint32)))
  cycleCompare(words, 1, 2, true)
  words.add(0x9a800000'u32 or (23'u32 shl 16) or (1'u32 shl 12) or
      (1'u32 shl 5) or 23'u32) # CSEL X23,X1,X23,NE.
  cycleImmediate(words, 1, uint64(shape.staticHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 1, 0)
  cycleEdge(words, fixes, 11, 16)

  labels[1] = words.len
  armMacroGuard(words, fixes, shape.staticSpan, shape.staticPrice, 6)
  armMacroCount(words, 20)
  cycleImmediate(words, 23, uint64(shape.staticHeader))
  cycleEdge(words, fixes, 2, 16) # Cached opcode40 target is the pure header.

  labels[2] = words.len
  armMacroGuard(words, fixes, shape.pureSpan, shape.purePrice, 7)
  cycleMove(words, 0, 19)
  if not cycleLinkChild(words, planned, pure.code-2): return false
  armMacroCount(words, 21)
  cycleImmediate(words, 23, uint64(shape.pureHeader))
  cycleImmediate(words, 1, uint64(shape.branchHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 3, 0)
  cycleEdge(words, fixes, 11, 16) # Genuine rare pure arm exits to checked C.

  labels[3] = words.len
  armMacroGuard(words, fixes, shape.branchSpan, shape.branchPrice, 8)
  var branchBody = default(ArmBlock)
  emitArmBranchSlots(branchBody, 88'u8, shape.branchSlot, 0,
      shape.branchImmediate, shape.branchYes, shape.branchNo)
  cycleMove(words, 0, 19)
  for instruction in armInstructions(branchBody): words.add(instruction)
  armMacroCount(words, 22)
  cycleImmediate(words, 23, uint64(shape.branchHeader))
  cycleImmediate(words, 1, uint64(shape.pureHeader))
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 2, 0) # Real branch88 backedge repeats pure's guard.
  cycleEdge(words, fixes, 4, 16)

  labels[4] = words.len
  armMacroGuard(words, fixes, shape.readSpan, shape.readPrice, 9)
  cycleMove(words, 0, 19)
  cycleLoad(words, 1, 20, 40) # Current invocation descriptors, not a cached address.
  if not cycleLinkChild(words, planned, read.code-2): return false
  words.add(0x12800001'u32) # MOVN W1,#0: guarded read refusal sentinel.
  cycleCompare(words, 0, 1, true)
  cycleEdge(words, fixes, 10, 0)
  armMacroCount(words, 23)
  cycleImmediate(words, 23, uint64(shape.readHeader))
  cycleEdge(words, fixes, 0, 16) # Cached opcode1 target is the cycle header.

  labels[6] = words.len
  cycleImmediate(words, 0, uint64(shape.staticHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[7] = words.len
  cycleImmediate(words, 0, uint64(shape.pureHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[8] = words.len
  cycleImmediate(words, 0, uint64(shape.branchHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[9] = words.len
  cycleImmediate(words, 0, uint64(shape.readHeader))
  cycleEdge(words, fixes, 11, 16)
  labels[10] = words.len
  cyclePriceChange(words, shape.readPrice, true)
  cycleAddImmediate(words, 22, 22, shape.readSpan)
  armMacroCount(words, 25)
  cycleImmediate(words, 0, uint64(shape.readHeader))
  cycleEdge(words, fixes, 11, 16)

  labels[11] = words.len
  cycleStore(words, 21, 20, 0)
  cycleStore(words, 22, 20, 8)
  cycleStore(words, 23, 20, 192)
  for pair in 0..<6:
    let first = uint32(19+pair*2)
    words.add(0xa9400000'u32 or (uint32(pair*2) shl 15) or
        ((first+1) shl 10) or (31'u32 shl 5) or first)
  words.add(0x910183ff'u32) # ADD SP,SP,#96; arena appends RET.
  if words.len == 0 or words.len >= 1024 or
      uint64(words.len+1)*4 > 1048576-jit.codeBytes or
      not armMacroPatch(words, fixes, labels): return false
  when defined(pvmArmMacroPublishRefuse):
    # Test the append-failure boundary after all same-owner children exist.
    return false
  words.add(0xd65f03c0'u32)
  let address = publishArena(jit.arena.handle, addr words[0], uint32(words.len))
  if address < 0: return false
  inc jit.fragments
  jit.codeBytes+=uint64(words.len)*4
  if uint64(address) != planned: return false
  jit.macroRoute.code = uint32(address)+2
  jit.macroRoute.imageWords = uint32(words.len)
  jit.macroRoute.shape = shape
  jit.macroRoute.cycleCode = root.code
  jit.macroRoute.pureCode = pure.code
  jit.macroRoute.readCode = read.code
  jit.macroRoute.pureOperations = pure.operations
  jit.macroRoute.readOperations = read.operations
  jit.macroRoute.residentMode = false
  jit.macroRoute.status = 2
  true

proc armMacroConserve(count: uint64, span: uint32, price: uint64,
    attempts, gas: var uint64) =
  ## Charge one source-owned semantic category without unchecked product overflow.
  assert span > 0 and count <= attempts div uint64(span)
  attempts-=count*uint64(span)
  if price > 0: assert count <= gas div price
  gas-=count*price

proc armMacroOperationTotal(total: var uint64, count: uint64, each: uint32) =
  ## Each counted instruction was lowered by a genuine child or scalar control.
  assert each > 0 and count <= (high(uint64)-total) div uint64(each)
  total+=count*uint64(each)

proc callArmMacroCore(jit: ArmJit, registers: var RegisterFile,
    descriptorPointer: pointer, dirtyWords: var seq[uint64],
    state: var ArmMacroState): uint32 =
  ## One outer bridge borrows fresh pointers; all nested semantic work is checked on return.
  ## The caller supplies fresh counters and both last-header sentinels. The cycle child
  ## uses word 13 and the enclosing macro uses word 24, so a child return cannot erase
  ## the continuation of the enclosing route.
  assert jit.macroRoute.status == 2 and sizeof(RegisterFile) == 104 and
      descriptorPointer != nil and sizeof(state) == 208
  for index in 2..12: assert state[index] == 0
  assert state[13] == uint64(high(uint32))
  for index in 14..23: assert state[index] == 0
  assert state[24] == uint64(high(uint32)) and state[25] == 0
  let gas = state[0]
  let available = state[1]
  state[5] = cast[uint64](descriptorPointer)
  state[6] = uint64(dirtyWords.len)
  state[7] = 0
  if dirtyWords.len > 0: state[7] = cast[uint64](addr dirtyWords[0])
  let shape = jit.macroRoute.shape
  let rare = if shape.pureYes == shape.branchHeader: shape.pureNo else: shape.pureYes
  result = regionArena(jit.arena.handle, jit.macroRoute.code-2,
      addr registers, addr state)
  assert result == shape.cycleHeader or result == jit.memoryCycle.dirtyHeader or
      result == jit.memoryCycle.tailHeader or result == shape.staticHeader or
      result == shape.pureHeader or result == shape.branchHeader or
      result == shape.readHeader or result == rare
  assert state[0] <= gas and state[1] <= available and state[4] == 0
  assert state[13] == uint64(high(uint32)) or
      state[13] == uint64(shape.cycleHeader) or
      state[13] == uint64(jit.memoryCycle.dirtyHeader) or
      state[13] == uint64(jit.memoryCycle.tailHeader)
  let last = state[24]
  assert last == uint64(high(uint32)) or last == uint64(shape.cycleHeader) or
      last == uint64(jit.memoryCycle.dirtyHeader) or
      last == uint64(jit.memoryCycle.tailHeader) or
      last == uint64(shape.staticHeader) or last == uint64(shape.pureHeader) or
      last == uint64(shape.branchHeader) or last == uint64(shape.readHeader)
  assert state[25] <= 1 and (state[25] == 0 or result == shape.readHeader)
  let prefix = state[14]
  let tail = state[15]
  let dirty = state[16]
  let wordGroups = state[17]
  let dirtyCalls = state[18]
  let childCalls = state[19]
  let staticBlocks = state[20]
  let pureBlocks = state[21]
  let branchBlocks = state[22]
  let readBlocks = state[23]
  assert childCalls > 0 and readBlocks < high(uint64) and
      childCalls == readBlocks+1 and staticBlocks <= childCalls and
      branchBlocks <= pureBlocks and readBlocks <= branchBlocks
  assert wordGroups <= dirty div 4 and dirtyCalls <= prefix and
      (dirtyCalls == 0 or dirty >= dirtyCalls-1)
  var attempted = available-state[1]
  var spent = gas-state[0]
  armMacroConserve(prefix, jit.memoryCycle.prefixSpan,
      jit.memoryCycle.prefixPrice, attempted, spent)
  armMacroConserve(tail, jit.memoryCycle.tailSpan,
      jit.memoryCycle.tailPrice, attempted, spent)
  armMacroConserve(dirty, jit.dirtyLoop.span,
      jit.dirtyLoop.price, attempted, spent)
  armMacroConserve(staticBlocks, shape.staticSpan,
      shape.staticPrice, attempted, spent)
  armMacroConserve(pureBlocks, shape.pureSpan,
      shape.purePrice, attempted, spent)
  armMacroConserve(branchBlocks, shape.branchSpan,
      shape.branchPrice, attempted, spent)
  armMacroConserve(readBlocks, shape.readSpan,
      shape.readPrice, attempted, spent)
  assert attempted == 0 and spent == 0
  var operations = 0'u64
  armMacroOperationTotal(operations, prefix, jit.memoryCycle.prefixOperations)
  armMacroOperationTotal(operations, tail, jit.memoryCycle.tailOperations)
  armMacroOperationTotal(operations, dirty, jit.dirtyLoop.operations)
  armMacroOperationTotal(operations, staticBlocks, 1)
  armMacroOperationTotal(operations, pureBlocks, jit.macroRoute.pureOperations)
  armMacroOperationTotal(operations, branchBlocks, 1)
  armMacroOperationTotal(operations, readBlocks,
      jit.macroRoute.readOperations+1) # Native read body plus canonical opcode1.
  assert operations <= high(uint64)-jit.operations
  inc jit.calls
  inc jit.branchCalls
  inc jit.headerCalls
  jit.operations+=operations
  inc jit.macroRoute.calls
  jit.macroRoute.cycleChildCalls+=childCalls
  jit.macroRoute.staticBlocks+=staticBlocks
  jit.macroRoute.pureBlocks+=pureBlocks
  jit.macroRoute.branchBlocks+=branchBlocks
  jit.macroRoute.readBlocks+=readBlocks
  jit.macroRoute.readRefusals+=state[25]
  jit.memoryCycle.prefixBlocks+=prefix
  jit.memoryCycle.tailBlocks+=tail
  jit.memoryCycle.dirtyBlocks+=dirty
  jit.memoryCycle.wordGroups+=wordGroups
  jit.memoryCycle.dirtyCalls+=dirtyCalls
  jit.dirtyLoop.calls+=dirtyCalls
  jit.dirtyLoop.blocks+=dirty
  jit.dirtyLoop.wordGroups+=wordGroups
  if result == jit.memoryCycle.dirtyHeader: inc jit.dirtyLoop.declines

proc callArmMacro*(jit: ArmJit, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var ArmMacroState): uint32 =
  ## Preserve the legacy 72-byte direct-witness ABI for a raw-only code owner.
  assert jit != nil and not jit.clippedReads and sizeof(regions) == 72
  callArmMacroCore(jit, registers, addr regions, dirtyWords, state)

proc callArmMacroContext*(jit: ArmJit, registers: var RegisterFile,
    context: var ArmReadContext, dirtyWords: var seq[uint64],
    state: var ArmMacroState): uint32 =
  ## Borrow the complete 144-byte frame context for one full-mode native entry.
  assert jit != nil and jit.clippedReads and sizeof(context) == 144
  callArmMacroCore(jit, registers, addr context, dirtyWords, state)
