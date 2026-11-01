# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## ARM64 scalar, guarded-memory and connected-block lowering with prepared source proofs.
## Code borrows invocation registers and guarded private memory; no invocation/source pointer is retained.
import std/assertions
import ../[program, machine]

when defined(pvmArmMixedGroupReceipt):
  const armMixedStateWords = 7
else:
  const armMixedStateWords = 5

type ArmMixedState* = array[armMixedStateWords, uint64]

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
    mixedCalls*, mixedCompleted*, mixedInterior*, mixedOperations*: uint64
    mixedGroupPublished, mixedGroupAttempts, mixedGroupPasses: uint64

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

proc newArmJit*(): ArmJit =
  ## Storage is allocated lazily only after a supported multi-operation fragment is identified.
  # Keep the same three-u32 logical payload per stream coordinate, without hidden record padding.
  assert sizeof(ArmEntryRecord) == 12
  ArmJit(arena: ArenaOwner(handle: nil), region: default(ArmRegionCache),
      dirtyLoop: default(ArmDirtyLoopCache), entries: @[],
      unavailable: false)

func supportedArmOpcode*(opcode: byte): bool =
  ## Non-exiting arithmetic remains independent of guest memory, branch selection and source accounting.
  opcode in {20'u8, 51, 100, 107..110, 131..143, 149..154, 158, 160,
      190..192, 197..202, 207..217, 222..226}

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

proc emitArmBranch*(fragment: var ArmBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64, yes, no: uint32) =
  ## Only positive cached branch capabilities supply scalar destinations; flags survive MOV/STR publication.
  assert opcode in {81'u8..90'u8, 170'u8..175'u8}
  assert yes < 2147483646'u32 and no < 2147483646'u32
  let left = armRead(fragment, slots.aIndex)
  var right = 1'u32
  if opcode <= 90:
    # Branch immediates retain GP signed low-word extension before full 64-bit comparison.
    # Keep ordinary branch layout fixed; a connected body owns a variable-length defining compare prefix.
    if fragment.compact: armCompactImmediate(fragment.terminal, 1, immediate)
    else: armImmediate(fragment.terminal, 1, immediate)
  else:
    right = armRead(fragment, slots.bIndex)
  fragment.terminal.add(0xeb00001f'u32 or (right shl 16) or (left shl 5)) # CMP Xn,Xm
  let condition = case opcode
    of 81, 170: 0'u32  # EQ
    of 82, 171: 1'u32  # NE
    of 83, 172: 3'u32  # CC, unsigned less
    of 84: 9'u32       # LS, unsigned less or equal
    of 85, 174: 2'u32  # CS, unsigned greater or equal
    of 86: 8'u32       # HI, unsigned greater
    of 87, 173: 11'u32 # LT, signed less
    of 88: 13'u32      # LE, signed less or equal
    of 89, 175: 10'u32 # GE, signed greater or equal
    else: 12'u32       # GT, signed greater
                   # Comparison precedes scratch reuse; these instructions do not change NZCV. X0 is overwritten only after stores.
  fragment.terminal.add(0x52800001'u32 or ((yes and 65535) shl 5))
  fragment.terminal.add(0x72a00001'u32 or ((yes shr 16) shl 5))
  fragment.terminal.add(0x52800002'u32 or ((no and 65535) shl 5))
  fragment.terminal.add(0x72a00002'u32 or ((no shr 16) shl 5))
  fragment.terminal.add(0x1a820020'u32 or (condition shl 12)) # CSEL W0,W1,W2,cond

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
  let loading = opcode >= 124
  let width = case opcode
    of 120, 124, 125: 1'u32
    of 121, 126, 127: 2'u32
    of 122, 128, 129: 4'u32
    else: 8'u32
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
  let loading = opcode >= 124
  let width = case opcode
    of 120, 124, 125: 1'u32
    of 121, 126, 127: 2'u32
    of 122, 128, 129: 4'u32
    else: 8'u32
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

proc emitArmReadFrom(span: var ArmReadSpan, baseSlot, destinationSlot: range[0..12],
    displacement: uint32, opcode: range[124..130], absolute: bool = false) =
  ## Indirect aliases consume the old base; a direct load has the specified immediate address.
  let source = if absolute: 31'u32 else: armRead(span.body, baseSlot)
  let destination = armWrite(span.body, destinationSlot)
  span.body.words.add(0x2a0003e3'u32 or (source shl 16)) # MOV W3,Wsource snapshots modulo-2^32 base.
  span.body.words.add(0x52800002'u32 or ((displacement and 65535) shl 5))
  span.body.words.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
  span.body.words.add(0x0b020063'u32) # ADD W3,W3,W2 wraps the effective address exactly once.
  span.body.words.add(0xf140407f'u32) # CMP X3,#65536 rejects the protected prefix.
  armReadRefusal(span, 0x54000003'u32, true) # LO exits before accessing a descriptor pointer.
  span.body.words.add(0x12800102'u32) # MOV W2,#0xfffffff7 preserves the existing conservative bound.
  span.body.words.add(0xeb02007f'u32) # CMP X3,X2.
  armReadRefusal(span, 0x54000008'u32, true) # HI retains canonical top-address handling.
  var accepted = default(array[3, int])
  for region in 0..<3:
    # X17 preserves the descriptor base across arithmetic's X1 scratch; X3 retains the address across region misses.
    span.body.words.add(0xa9400a21'u32 or (uint32(region*3) shl 15)) # LDP X1,X2,[X17,#region*24].
    span.body.words.add(0xcb010061'u32) # SUB X1,X3,X1 computes an unsigned region offset.
    span.body.words.add(0xeb02003f'u32) # CMP X1,X2 proves offset < extent-minus-seven.
    span.body.words.add(0x54000082'u32) # HS skips exactly the pointer, load and accepted branch.
    span.body.words.add(0xf9400222'u32 or (uint32(region*3+2) shl 10)) # LDR X2,[X17,#region*24+16].
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
  emitArmReadFrom(span, slots.bIndex, slots.aIndex, displacement, opcode)

proc emitArmDirectRead*(span: var ArmReadSpan, slots: RegisterSlots, displacement: uint32,
    opcode: range[52..58]) =
  ## Direct loads have an absolute modulo-2^32 immediate address and publish A only on success.
  emitArmReadFrom(span, slots.aIndex, slots.aIndex, displacement,
      range[124..130](int(opcode)+72), true)

proc beginArmReadWindow*(span: var ArmReadSpan, slot: range[0..12], first, last: uint32) =
  ## A stable guest base admits one nonwrapping readable window before any speculative register mutation.
  assert span.body.words.len == 0 and last >= first and last-first <= 4088
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
  emitArmBranch(span.body, opcode, slots, immediate, yes, no)

proc armReadInstructions*(span: ArmReadSpan, ending: uint32,
    conditional: bool = false): seq[uint32] =
  ## No guest register store precedes a successful complete read sequence; refused speculation has no visible prefix.
  assert (span.body.terminal.len > 0) == conditional
  result = @[0xaa0103f1'u32] # MOV X17,X1 retains only this invocation's borrowed descriptors.
  var leading = 0
  for slot in 0..<13:
    # armInstructions prefixes exactly one original-value load for each live-in guest slot.
    if (span.body.reads and (1'u32 shl slot)) != 0: inc leading
  for word in armInstructions(span.body): result.add(word)
  if not conditional:
    result.add(0x52800000'u32 or ((ending and 65535) shl 5))
    result.add(0x72a00000'u32 or ((ending shr 16) shl 5))
  result.add(0xd65f03c0'u32) # Success returns after the sole complete register publication.
  let failure = result.len
  result.add(0x12800000'u32) # Refusal returns flatStop; arena publication appends RET.
  assert result.len < 8192 # Sixty-four admitted source operations fit every forward refusal displacement.
  for guard in span.guards:
    # The initial context move and live-in loads shift every body-relative branch equally.
    let at = guard.at+leading+1
    assert at >= 1 and at < failure
    let distance = uint32(failure-at)
    result[at] = result[at] or (if guard.conditional: distance shl 5 else: distance)


proc armMemoryInstructions*(fragment: var ArmBlock, slots: RegisterSlots,
    displacement, ending: uint32, opcode: range[124..130] = 130): seq[uint32] =
  ## A first indirect read of the selected signed/unsigned width guards fresh borrowed regions before any guest register is published.
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
  result.add(0x52800002'u32 or ((displacement and 65535) shl 5))
  result.add(0x72a00002'u32 or ((displacement shr 16) shl 5))
  result.add(0x0b020063'u32) # ADD Waddress,Waddress,Wdisplacement implements genuine modulo-2^32 addressing.
  result.add(0xf140407f'u32) # CMP Xaddress,#65536 rejects the protected prefix.
  var refused: seq[int] = @[result.len]
  result.add(0x54000003'u32) # LO returns untouched to canonical memory preflight.
  result.add(0x12800102'u32) # MOV Wlimit,#0xfffffff7, matching the existing conservative fast-load bound.
  result.add(0xeb02007f'u32) # CMP Xaddress,Xlimit.
  refused.add(result.len)
  result.add(0x54000008'u32) # HI returns untouched for top-address scalar handling.
  var accepted: seq[int] = @[]
  for region in 0..<3:
    # Unsigned subtraction rejects addresses below a region; offset < length-7 proves the complete eight-byte extent.
    result.add(0xa9404422'u32 or (uint32(region*3) shl 15)) # LDP Xbase,Xextent,[Xcontext,#region*24].
    result.add(0xcb020062'u32) # SUB Xoffset,Xaddress,Xbase.
    result.add(0xeb11005f'u32) # CMP Xoffset,Xextent.
    result.add(0x54000082'u32) # HS skips this region without reading its pointer.
    result.add(0xf9400031'u32 or (uint32(region*3+2) shl 10)) # LDR Xpointer,[Xcontext,#region*24+16].
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

proc armPendingMemoryEnding*(jit: ArmJit, offset, ending: uint32) =
  ## A deferred read/branch fragment occupies no executable slot until both original branch arms are cached.
  assert int(offset) < jit.entries.len and jit.entries[int(offset)].code == 0
  assert ending > offset
  jit.entries[int(offset)].code = 1
  jit.entries[int(offset)].ending = ending

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
    instructions: var seq[uint32], region: bool = false): bool =
  ## Reserve one of the same 1,024 publication slots for a connected loop; OS/capacity refusal preserves checked execution.
  if jit.unavailable:
    # Only initial allocation refusal is sticky; a cache with any published code can never enter this state.
    refuseArmEntry(jit, offset)
    return false
  let ceiling = if region: 1024'u64 else: 1023'u64
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
  instructions.add(0xd65f03c0'u32) # RET; the leaf never changes SP, LR or any callee-saved register.
  let address = publishArena(jit.arena.handle, addr instructions[0], uint32(instructions.len))
  if address < 0:
    refuseArmEntry(jit, offset)
    return false
  jit.entries[int(offset)] = ArmEntryRecord(code: uint32(address)+2, operations: count,
      ending: ending)
  inc jit.fragments
  jit.codeBytes+=uint64(instructions.len)*4
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

proc callArmMemory*(jit: ArmJit, offset: uint32, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]]): uint32 =
  ## The code borrows only this frame's descriptors; refusal publishes no guest mutation and charges no lowered operations.
  assert sizeof(RegisterFile) == 104 and sizeof(regions) == 72
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  result = regionArena(jit.arena.handle, entry.code-2, addr registers, addr regions)
  assert result == high(uint32) or result == entry.ending
  inc jit.calls
  if result != high(uint32): jit.operations+=uint64(entry.operations)

proc callArmMemoryBranch*(jit: ArmJit, offset, yes, no: uint32,
    registers: var RegisterFile, regions: var array[3, array[3, uint64]]): uint32 =
  ## A refused read leaves the original registers untouched; success selects only cached branch arms.
  assert sizeof(RegisterFile) == 104 and sizeof(regions) == 72
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2
  result = regionArena(jit.arena.handle, entry.code-2, addr registers, addr regions)
  assert result == high(uint32) or result == yes or result == no
  inc jit.calls
  if result != high(uint32):
    inc jit.branchCalls
    jit.operations+=uint64(entry.operations)

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

proc callArmMixed*(jit: ArmJit, header: uint32, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var ArmMixedState): uint32 =
  ## The checked header owns gas and attempt reservation; native owns only this body's prefix.
  assert sizeof(RegisterFile) == 104 and sizeof(regions) == 72
  assert int(header) < jit.entries.len and jit.entries[int(header)].code >= 2
  let entry = jit.entries[int(header)]
  state[0] = 0
  state[1] = cast[uint64](addr regions)
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

proc publishArmRegion*(jit: ArmJit, blocks: array[3, ArmRegionBlock],
    count: range[2..3] = 3): bool =
  ## Compile one already-validated closed loop with resident registers and complete gas/source guards at every block.
  assert jit.region.status == 0
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
  for index in 0..<count:
    # Only bounded complete source spans with an actual terminal branch may enter this narrow region compiler.
    let item = blocks[index]
    if item.span < 2 or item.span > 4095 or item.operations < 2 or item.operations > item.span:
      return false
    if item.body.terminal.len notin [6, 10]:
      # Only our explicit regional policy can shorten the compare constant; the final five return words remain fixed.
      if not item.body.compact or item.body.terminal.len < 7 or item.body.terminal.len > 9:
        return false
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
  if words.len >= 1024: return false
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
    assert count > 0 and span >= count and state[index+2] <= consumed div span
    let attempts = state[index+2]*span
    assert accounted <= consumed and attempts <= consumed-accounted
    accounted+=attempts
    jit.operations+=state[index+2]*count
    jit.region.blocks+=state[index+2]
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
  var words: seq[uint32] = @[0xaa0103f1'u32, 0xf9400222'u32, 0xf9400623'u32,
      0xfd400a30'u32, 0xfd400e31'u32, 0xfd401232'u32, 0xd2800021'u32, 0x9e670033'u32]
  var fixes: seq[ArmRegionFixup] = @[]
  var resident = item.body.reads or item.body.writes or (1'u32 shl int(baseSlot))
  var written = item.body.writes
  if word.enabled:
    # The optional word lowering has additional explicit inputs and writes.
    for slot in [word.source, word.shift, word.destination, word.base, word.bound]:
      resident = resident or (1'u32 shl int(slot))
    for slot in [word.destination, word.base, word.shift]:
      written = written or (1'u32 shl int(slot))
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
  for slot in 0..<13:
    if (written and (1'u32 shl slot)) != 0:
      words.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
  words.add(0xf9000222'u32)
  words.add(0xf9000623'u32)
  words.add(0xfd000a30'u32)
  words.add(0xfd000e31'u32)
  words.add(0xfd001232'u32)
  words.add(0x2a0103e0'u32)
  if words.len >= 1024: return false
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

proc callArmDirtyLoop*(jit: ArmJit, registers: var RegisterFile,
    regions: var array[3, array[3, uint64]], dirtyWords: var seq[uint64],
    state: var array[8, uint64]): uint32 =
  ## All invocation pointers are borrowed only across this one native call.
  assert jit.dirtyLoop.status == 2 and sizeof(RegisterFile) == 104 and sizeof(regions) == 72
  assert state[2] == 0 and state[3] == 0 and state[4] == 0
  let gas = state[0]
  let available = state[1]
  state[5] = cast[uint64](addr regions)
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

func armDirtyLoopStatistics*(jit: ArmJit): array[3, uint64] =
  [jit.dirtyLoop.calls, jit.dirtyLoop.blocks, jit.dirtyLoop.declines]

func armDirtyWordGroups*(jit: ArmJit): uint64 =
  jit.dirtyLoop.wordGroups
