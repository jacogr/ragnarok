# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Experimental ARM64 compiler for sealed register fragments and guarded connected blocks.
## Code borrows invocation registers and a bounded scalar context, never guest/source pointers.
import std/assertions
import ../[program, machine]

proc armClock*(): uint64 {.cdecl, importc: "pvm_arm64_jit_cpu_ns", header: "arm64_memory.h".}
proc createArenaNative(): nil pointer {.cdecl, importc: "pvm_arm64_arena_create",
    header: "arm64_memory.h".}
proc destroyArena(arena: nil pointer) {.cdecl, importc: "pvm_arm64_arena_destroy",
    header: "arm64_memory.h".}
proc publishArena(arena: nil pointer, words: pointer,
    count: uint32): int32 {.cdecl, importc: "pvm_arm64_arena_publish", header: "arm64_memory.h".}
proc callArena(arena: nil pointer, offset: uint32,
    registers: pointer): cint {.cdecl, importc: "pvm_arm64_arena_call", header: "arm64_memory.h".}

proc nextArena(arena: nil pointer, offset: uint32,
    registers: pointer): uint32 {.cdecl, importc: "pvm_arm64_arena_next", header: "arm64_memory.h".}

proc regionArena(arena: nil pointer, offset: uint32, registers, state: pointer): uint32 {.cdecl,
    importc: "pvm_arm64_arena_region", header: "arm64_memory.h".}

type
  ArmEntryRecord = object ## Executable records bind code, operation count and successor; uncompiled headers may hold a bounded probe budget.
    code, operations, ending: uint32
  ArmRegionCache = object ## One bounded connected loop retains only exact-source scalar proofs and counters.
    status: uint8
    headers, spans, operations: array[3, uint32]
    prices: array[3, uint64]
    calls, blocks: uint64
    blockCount: uint32 # Active two/three-block shape; unused counter lanes remain zero.
  ArmBlock* = object ## A bounded leaf keeps guest registers in X4–X16, loading live-ins and publishing only dirty slots.
    words, terminal: seq[uint32]
    reads, writes: uint32
    compact: bool
  ArenaOwner = object ## Move-only OS allocation; the containing reference shares no mutable invocation state.
    handle: nil pointer
  ArmJit* = ref object ## Exclusive frame-owned compiler cache; no executable image escapes its arena owner.
    arena: ArenaOwner
    region: ArmRegionCache
    entries: seq[ArmEntryRecord]
    branchCalls*, headerCalls*: uint64
    fragments*: uint64
    calls*, operations*, codeBytes*, compilationNs*: uint64
    unavailable: bool

proc `=copy`(destination: var ArenaOwner, source: ArenaOwner) {.error.}
proc `=dup`(source: ArenaOwner): ArenaOwner {.error.}
proc `=destroy`(owner: ArenaOwner) =
  ## A default or moved-from owner has no executable mapping to release.
  if owner.handle != nil: destroyArena(owner.handle)

proc createArena(): nil pointer =
  ## Local refusal controls prove that unavailable executable storage preserves checked fallback.
  when defined(pvmArm64JitRefuse): nil
  else: createArenaNative()

proc newArmJit*(): ArmJit =
  ## Storage is allocated lazily only after a supported multi-operation fragment is identified.
  # Keep the same three-u32 logical payload per stream coordinate, without hidden record padding.
  assert sizeof(ArmEntryRecord) == 12
  ArmJit(arena: ArenaOwner(handle: nil), region: default(ArmRegionCache), entries: @[],
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


type
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
  ## Zero allows one compile attempt, one is refused, and two denotes an immutable published region.
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

proc publishArmRegion*(jit: ArmJit, blocks: array[3, ArmRegionBlock],
    count: range[2..3] = 3): bool =
  ## Compile one already-validated closed loop with resident registers and complete gas/source guards at every block.
  assert jit.region.status == 0
  jit.region.status = 1 # Any refusal remains interpreted and avoids repeated compilation attempts.
  # D16..D19 are caller-saved SIMD lanes distinct from the X-register file; integer ADD preserves all 64 counter bits.
  var words: seq[uint32] = @[0xaa0103f1'u32, 0xf9400222'u32, 0xf9400623'u32,
      0xfd400a30'u32, 0xfd400e31'u32, 0xfd401232'u32, 0xd2800021'u32, 0x9e670033'u32]
  var fixes: seq[ArmRegionFixup] = @[]
  var labels = default(array[3, int])
  var exits: seq[uint32] = @[]
  var exitLabels: seq[int] = @[]
  # All thirteen values are live on entry; linear dirty/live-in inference is insufficient across loop paths.
  for slot in 0..<13: words.add(0xf9400000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
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
  for slot in 0..<13: words.add(0xf9000000'u32 or (uint32(slot) shl 10) or uint32(slot+4))
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
