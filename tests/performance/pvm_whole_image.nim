# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private gas-free ARM64 whole-program compiler. Every guest edge stays in one owned native image.
## Checked memory callbacks borrow our actual ScalarMemoryWriter; there is no interpreter fallback.
import std/assertions
import ../../src/pvm/[program, machine]

type
  Invocation* = object
    registers*: array[13, uint64] ## Complete CPU register publication only at the real image exit.
    status*, pc*, fault_page*, loads*, stores*, exits*: uint64
    writer*: nil pointer          ## Borrowed ScalarMemoryWriter; its Nim owner must outlive the native call.
  LoadCallback = proc(raw: pointer, address, width: uint64): uint64 {.cdecl, raises: [].}
  StoreCallback = proc(raw: pointer, address, value, width: uint64) {.cdecl, raises: [].}
  ImageOwner = object ## Raw executable ownership is separate from compiler-managed source ARC ownership.
    handle: nil pointer
  WholeImage* = object ## Move-only immutable executable allocation, bound to one immutable source owner.
    owner: ImageOwner
    source: Program
    codeBytes*, instructions*: uint64
    opcodes*: array[256, uint64]
  Fixup = object ## A direct branch is bound to a genuine immutable source coordinate.
    at: int
    pc: uint64
  Builder = object ## Cold compilation owns all relocations; invocation state never enters this graph.
    words: seq[uint32]
    labels: seq[int]
    fixups: seq[Fixup]
    exits: seq[int]
    halts: seq[int]
    panics: seq[int]
    tableLoads: seq[int]

proc createdCountNative(): uint64 {.cdecl, importc: "pvm_whole_created_count",
    header: "pvm_whole_image.h".}
proc destroyedCountNative(): uint64 {.cdecl, importc: "pvm_whole_destroyed_count",
    header: "pvm_whole_image.h".}
proc cpuNs*(): uint64 {.cdecl, importc: "pvm_whole_cpu_ns", header: "pvm_whole_image.h".}
proc wallNs*(): uint64 {.cdecl, importc: "pvm_whole_wall_ns", header: "pvm_whole_image.h".}
proc checkLayout(raw: pointer): cint {.cdecl, importc: "pvm_whole_check_layout",
    header: "pvm_whole_image.h".}
proc contextSize(): uint32 {.cdecl, importc: "pvm_whole_context_size", header: "pvm_whole_image.h".}
proc publish(words: pointer, count: uint): nil pointer {.cdecl, importc: "pvm_whole_publish",
    header: "pvm_whole_image.h".}
proc destroyImage(handle: nil pointer) {.cdecl, importc: "pvm_whole_destroy",
    header: "pvm_whole_image.h".}
proc callImage(handle: nil pointer, context: pointer, load: LoadCallback,
    store: StoreCallback): cint {.cdecl, importc: "pvm_whole_call", header: "pvm_whole_image.h".}

proc `=copy`(destination: var ImageOwner, source: ImageOwner) {.error.}
proc `=dup`(source: ImageOwner): ImageOwner {.error.}
proc `=wasMoved`(image: var ImageOwner) {.nodestroy, inline.} =
  ## A moved native allocation has no mapping left to release.
  image.handle = nil
proc `=destroy`(image: ImageOwner) =
  ## Default and moved-from raw owners are inert; the composite automatically destroys its source child.
  if image.handle != nil: destroyImage(image.handle)
proc `=copy`*(destination: var WholeImage, source: WholeImage) {.error.}
proc `=dup`*(source: WholeImage): WholeImage {.error.}

func reg(slot: range[0..12]): uint32 =
  ## Ten guest values use callee-saved registers; three caller-saved values spill only at memory calls.
  if slot < 10: uint32(slot+19) else: uint32(slot-1)

func supportedPure(opcode: byte): bool =
  ## Non-exiting arithmetic remains independent of guest memory, branch selection and source accounting.
  opcode in {20'u8, 51, 100, 107..110, 131..143, 149..154, 158, 160,
      190..192, 197..202, 207..217, 222..226}

proc emitImmediate(words: var seq[uint32], destination: uint32, value: uint64) =
  ## Choose MOVZ or MOVN plus only differing halfwords; every sequence initializes all sixty-four bits.
  assert destination <= 30
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


proc emitBase(words: var seq[uint32], opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  ## Each instruction consumes original operands before declaring its destination; native aliases obey GP ordering.
  assert supportedPure(opcode)
  if opcode in [20'u8, 51]:
    # Immediate loads have no register live-in; their destination may previously be undefined in the leaf.
    let destination = reg(slots.destinationIndex)
    emitImmediate(words, destination, immediate)
    return
  if opcode == 100 or opcode in {107'u8..110'u8}:
    # Unary operations read the genuine A slot; every result is full-width, including signed extension.
    let source = reg(slots.aIndex)
    let destination = reg(slots.destinationIndex)
    let operation = case opcode
      of 107: 0x93401c00'u32 # SXTB Xd,Wn
      of 108: 0x93403c00'u32 # SXTH Xd,Wn
      of 109: 0xd3403c00'u32 # UXTH Xd,Xn
      of 110: 0xdac00c00'u32 # REV Xd,Xn
      else: 0xaa0003e0'u32   # MOV Xd,Xn (ORR Xd,XZR,Xn)
    words.add(operation or (source shl (if opcode == 100: 16 else: 5)) or destination)
    return
  var left = 0'u32
  var right = 0'u32
  if opcode < 190:
    # Immediate arithmetic reads B; X1 is scratch and cannot alias the resident guest register bank.
    left = reg(slots.bIndex)
    emitImmediate(words, 1, immediate)
    right = 1
  else:
    # Three-register arithmetic snapshots both source coordinates before recording a destination write.
    left = reg(slots.aIndex)
    right = reg(slots.bIndex)
  if opcode in [141'u8, 154]:
    # Negated-add immediate is immediate minus B, preserving operand order without an intermediate mutation.
    let original = left
    left = right
    right = original
  let destination = reg(slots.destinationIndex)
  if opcode in {136'u8, 137, 142, 143, 216, 217}:
    # CMP consumes both original operands before CSET zero-extends a literal Boolean into an aliased destination.
    let condition = case opcode
      of 136, 216: 3'u32  # LO: unsigned less.
      of 137, 217: 11'u32 # LT: signed less.
      of 142: 8'u32       # HI: unsigned greater.
      else: 12'u32        # GT: signed greater.
    words.add(0xeb00001f'u32 or (right shl 16) or (left shl 5))
    words.add(0x1a9f07e0'u32 or ((condition xor 1'u32) shl 12) or destination)
    return
  if opcode == 215:
    # Form sign(A)&B in scratch before UMULH can overwrite either source; mixed signedness subtracts this correction.
    words.add(0x937ffc01'u32 or (left shl 5)) # ASR X1,Xn,#63.
    words.add(0x8a000021'u32 or (right shl 16)) # AND X1,X1,Xm.
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
  words.add(operation or (right shl 16) or (left shl 5) or destination)
  if opcode == 215:
    # The correction is already independent of aliased source registers; subtraction wraps to the exact upper word.
    words.add(0xcb010000'u32 or (destination shl 5) or destination)
  if opcode in {131'u8, 135, 138..141, 160, 190..192, 197..199, 223}:
    # ARM word operations zero high bits; GP requires sign extension of the low 32-bit result.
    words.add(0x93407c00'u32 or (destination shl 5) or destination)


proc emitOperation(words: var seq[uint32], opcode: byte, slots: RegisterSlots,
    value: uint64): bool =
  ## Every supported arithmetic opcode is encoded directly; no callback can evaluate an opcode.
  let a = reg(slots.aIndex)
  let b = reg(slots.bIndex)
  let d = reg(slots.destinationIndex)
  case opcode
  of 103, 104:
    words.add((if opcode == 104: 0x5ac01000'u32 else: 0xdac01000'u32) or (a shl 5) or d)
  of 105, 106:
    words.add((if opcode == 106: 0x5ac00000'u32 else: 0xdac00000'u32) or (a shl 5) or 1)
    words.add((if opcode == 106: 0x5ac01000'u32 else: 0xdac01000'u32) or (1'u32 shl 5) or d)
  of 144..148, 155..157, 159, 161:
    emitImmediate(words, 1, value)
    if opcode in [147'u8, 148]:
      words.add(0xf100001f'u32 or (b shl 5)) # CMP B,#0, before an aliased destination changes.
      words.add(0x9a800000'u32 or (d shl 16) or (uint32(opcode-147) shl 12) or (1'u32 shl 5) or d)
    else:
      let operation = case opcode
        of 144: 0x1ac02000'u32
        of 145: 0x1ac02400'u32
        of 146: 0x1ac02800'u32
        of 155: 0x9ac02000'u32
        of 156: 0x9ac02400'u32
        of 157: 0x9ac02800'u32
        of 159: 0x9ac02c00'u32
        else: 0x1ac02c00'u32
      words.add(operation or (b shl 16) or (1'u32 shl 5) or d)
      if opcode in [144'u8, 145, 146, 161]: words.add(0x93407c00'u32 or (d shl 5) or d)
  of 205:
    words.add(0x9ac00801'u32 or (b shl 16) or (a shl 5)) # UDIV X1,A,B returns zero for B=0.
    words.add(0x9b008000'u32 or (b shl 16) or (a shl 10) or (1'u32 shl 5) or
        d) # MSUB preserves A at zero divisor.
  of 218, 219:
    words.add(0xf100001f'u32 or (b shl 5))
    words.add(0x9a800000'u32 or (d shl 16) or (uint32(opcode-218) shl 12) or (a shl 5) or d)
  of 220, 221:
    words.add(0xcb0003e1'u32 or (b shl 16)) # NEG X1,B supplies modulo-width left rotation.
    words.add((if opcode == 221: 0x1ac02c00'u32 else: 0x9ac02c00'u32) or (1'u32 shl 16) or (
        a shl 5) or d)
    if opcode == 221: words.add(0x93407c00'u32 or (d shl 5) or d)
  of 227..230:
    words.add(0xeb00001f'u32 or (b shl 16) or (a shl 5))
    let condition = case opcode
      of 227: 10'u32
      of 228: 2'u32
      of 229: 11'u32
      else: 3'u32
    words.add(0x9a800000'u32 or (b shl 16) or (condition shl 12) or (a shl 5) or d)
  else:
    if not supportedPure(opcode): return false
    emitBase(words, opcode, slots, value)
  true

proc loadWord(words: var seq[uint32], target, base: uint32, offset: int) =
  ## Fixed ABI fields use aligned eight-byte unsigned offsets.
  assert target < 31 and base <= 31 and offset >= 0 and offset mod 8 == 0 and offset div 8 <= 4095
  words.add(0xf9400000'u32 or (uint32(offset div 8) shl 10) or (base shl 5) or target)

proc storeWord(words: var seq[uint32], source, base: uint32, offset: int) =
  ## No emitted store can address arbitrary host storage; bases are this invocation or its fixed native stack frame.
  assert source < 31 and base <= 31 and offset >= 0 and offset mod 8 == 0 and offset div 8 <= 4095
  words.add(0xf9000000'u32 or (uint32(offset div 8) shl 10) or (base shl 5) or source)

proc patchBranch(words: var seq[uint32], at, target: int) =
  ## Whole-image B26 reaches within the independently bounded 32MiB diagnostic image.
  assert at >= 0 and at < words.len and target >= 0 and target <= words.len
  let delta = int64(target)-int64(at)
  assert delta > -33554432 and delta < 33554432
  let encoded = if delta >= 0: uint32(delta) else: uint32(67108864'i64+delta)
  words[at] = 0x14000000'u32 or encoded

proc branch(words: var seq[uint32]): int =
  ## Relocation placeholders exist only before the image is published.
  result = words.len
  words.add(0x14000000'u32)

proc conditional(words: var seq[uint32], condition: uint32): int =
  ## Invert one short condition to skip a relocatable B26, avoiding conditional range limits.
  assert condition <= 13
  words.add(0x54000040'u32 or (condition xor 1'u32))
  branch(words)

proc setPc(words: var seq[uint32], pc: uint64) =
  ## Only fault/real-exit metadata is published during execution; normal block transitions need no handoff.
  loadWord(words, 12, 31, 96)
  emitImmediate(words, 3, pc)
  storeWord(words, 3, 12, 112)

proc fail(builder: var Builder, pc: uint64) =
  ## An invalid guest destination is a real panic exit, never an interpreter retry.
  setPc(builder.words, pc)
  builder.panics.add(branch(builder.words))

proc recordFailure(context: ptr Invocation, reason: MachineError, page: uint64) =
  ## Borrowed checked memory publishes an exact typed failure without a partial register result.
  context.status = if reason == MachineError.Fault: 3'u64 elif reason ==
      MachineError.Panic: 2'u64 else: 4'u64
  context.fault_page = page

proc checkedLoad(raw: pointer, address, width: uint64): uint64 {.cdecl, raises: [].} =
  ## The same real scalar writer supplies permission, prefix, wrapping and cross-page checks.
  let context = cast[ptr Invocation](raw)
  inc context.loads
  let writer {.cursor.} = cast[ScalarMemoryWriter](context.writer)
  let read = load(writer, MemoryAddress(address), AccessWidth(byte(width)))
  if read.error != MachineError.None:
    let page = if read.error == MachineError.Fault: uint64(read.faultPage) else: 0'u64
    recordFailure(context, read.error, page)
    return 0
  uint64(read.value)

proc checkedStore(raw: pointer, address, value, width: uint64) {.cdecl, raises: [].} =
  ## COW staging belongs to our real writer; failed stores retain its all-or-nothing mutation contract.
  let context = cast[ptr Invocation](raw)
  inc context.stores
  let writer {.cursor.} = cast[ScalarMemoryWriter](context.writer)
  let written = store(writer, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(value))
  if written.error != MachineError.None:
    let page = if written.error == MachineError.Fault: uint64(written.faultPage) else: 0'u64
    recordFailure(context, written.error, page)

proc emitMemory(builder: var Builder, decoded: ProgramResult[Instruction]) =
  ## All arithmetic/control stays native; only genuine memory accesses cross these counted C ABI helpers.
  let item = decoded.value
  let slots = instructionRegisters(decoded)
  let access = instructionMemoryOperands(decoded)
  setPc(builder.words, uint64(item.address))
  for i in 0..<3: storeWord(builder.words, uint32(i+9), 31, 120+i*8)
  emitImmediate(builder.words, 1, uint64(item.x) and 0xffffffff'u64)
  case access.base
  of MemoryBase.A:
    builder.words.add(0x0b010001'u32 or (reg(slots.aIndex) shl 5))
  of MemoryBase.B:
    builder.words.add(0x0b010001'u32 or (reg(slots.bIndex) shl 5))
  else: discard # Absolute addresses are already narrowed to the guest's cyclic32 domain.
  if access.isLoad:
    emitImmediate(builder.words, 2, uint64(access.width))
    loadWord(builder.words, 12, 31, 104)
  else:
    if access.usesImmediate: emitImmediate(builder.words, 2, uint64(item.y))
    else: builder.words.add(0xaa0003e2'u32 or (reg(slots.aIndex) shl 16))
    emitImmediate(builder.words, 3, uint64(access.width))
    loadWord(builder.words, 12, 31, 112)
  loadWord(builder.words, 0, 31, 96)
  builder.words.add(0xd63f0180'u32) # BLR X12; only this checked-memory boundary calls host code.
  for i in 0..<3: loadWord(builder.words, uint32(i+9), 31, 120+i*8)
  loadWord(builder.words, 12, 31, 96)
  loadWord(builder.words, 13, 12, 104)
  builder.words.add(0xf10001bf'u32) # CMP X13,#0.
  builder.exits.add(conditional(builder.words, 1))
  if access.isLoad:
    if access.isSigned:
      let bits = uint32(access.width)*8
      builder.words.add(0x93400000'u32 or ((bits-1) shl 10)) # SBFM X0,X0,#0,#bits-1.
    builder.words.add(0xaa0003e0'u32 or (0'u32 shl 16) or reg(slots.aIndex))

proc enter(builder: var Builder) =
  ## One AAPCS64 entry saves callee state and keeps thirteen guest registers resident across every block.
  builder.words.add(0xd10403ff'u32) # SUB SP,SP,#256.
  storeWord(builder.words, 29, 31, 0)
  storeWord(builder.words, 30, 31, 8)
  builder.words.add(0x910003fd'u32) # MOV FP,SP.
  for i in 0..<10: storeWord(builder.words, uint32(i+19), 31, 16+i*8)
  storeWord(builder.words, 0, 31, 96)
  storeWord(builder.words, 1, 31, 104)
  storeWord(builder.words, 2, 31, 112)
  let bytes = builder.words.len*4
  assert bytes < 1048576
  let displacement = uint32(2097152-bytes)
  builder.words.add(0x1000000e'u32 or ((displacement and 3) shl 29) or ((
      displacement shr 2) shl 5)) # ADR X14,entry.
  storeWord(builder.words, 14, 31, 144)
  for i in 0..<13: loadWord(builder.words, reg(i), 0, i*8)

proc finish(builder: var Builder) =
  ## Exactly one native epilogue publishes CPU state and returns after completion or a genuine failure.
  let halt = builder.words.len
  loadWord(builder.words, 12, 31, 96)
  emitImmediate(builder.words, 1, 1)
  storeWord(builder.words, 1, 12, 104)
  emitImmediate(builder.words, 1, 0)
  storeWord(builder.words, 1, 12, 112)
  builder.exits.add(branch(builder.words))
  let panic = builder.words.len
  loadWord(builder.words, 12, 31, 96)
  emitImmediate(builder.words, 1, 2)
  storeWord(builder.words, 1, 12, 104)
  let terminal = builder.words.len
  loadWord(builder.words, 12, 31, 96)
  # Both explicit/control panics and checked-memory panics normalize PC to zero; faults retain their source PC.
  loadWord(builder.words, 1, 12, 104)
  builder.words.add(0xf100083f'u32) # CMP X1,#2.
  builder.words.add(0x54000061'u32) # B.NE +12 skips only the panic PC normalization.
  emitImmediate(builder.words, 1, 0)
  storeWord(builder.words, 1, 12, 112)
  for i in 0..<13: storeWord(builder.words, reg(i), 12, i*8)
  loadWord(builder.words, 1, 12, 144)
  builder.words.add(0x91000421'u32) # ADD X1,X1,#1 counts a genuine native exit.
  storeWord(builder.words, 1, 12, 144)
  for i in 0..<10: loadWord(builder.words, uint32(i+19), 31, 16+i*8)
  loadWord(builder.words, 29, 31, 0)
  loadWord(builder.words, 30, 31, 8)
  builder.words.add(0x910403ff'u32) # ADD SP,SP,#256.
  builder.words.add(0xd65f03c0'u32) # The only RET in this whole-program image.
  for at in builder.halts: patchBranch(builder.words, at, halt)
  for at in builder.panics: patchBranch(builder.words, at, panic)
  for at in builder.exits: patchBranch(builder.words, at, terminal)

proc invoke*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile): Invocation =
  ## The caller retains the genuine source/writer while this synchronous call borrows both.
  assert image.owner.handle != nil and contextSize() == uint32(sizeof(Invocation))
  var context = default(Invocation)
  for i in 0..<13: context.registers[i] = uint64(registers[i])
  context.writer = cast[pointer](writer)
  assert callImage(image.owner.handle, addr context, checkedLoad, checkedStore) == 1
  context.writer = nil # No borrowed host pointer escapes a completed invocation.
  context

proc emitDynamic(builder: var Builder, item: Instruction, slots: RegisterSlots, jumps: int) =
  ## The source jump table becomes a native offset table; dynamic guest calls/returns never enter an interpreter.
  setPc(builder.words, uint64(item.address))
  let base = if item.opcode == 50: reg(slots.aIndex) else: reg(slots.bIndex)
  let delta = if item.opcode == 50: uint64(item.x) else: uint64(item.y)
  emitImmediate(builder.words, 1, delta and 0xffffffff'u64)
  builder.words.add(0x0b010001'u32 or (base shl 5)) # ADD W1,Wbase,W1 snapshots the original address operand.
  if item.opcode == 180: emitImmediate(builder.words, reg(slots.aIndex), uint64(item.x))
  emitImmediate(builder.words, 2, 0xffff0000'u64)
  builder.words.add(0x6b02003f'u32) # CMP W1,W2 checks the exact low32 halt sentinel first.
  builder.halts.add(conditional(builder.words, 0))
  builder.words.add(0x7100003f'u32) # CMP W1,#0.
  builder.panics.add(conditional(builder.words, 0))
  builder.words.add(0x36000041'u32) # TBZ W1,#0,+8 accepts only aligned positive dynamic addresses.
  builder.panics.add(branch(builder.words))
  builder.words.add(0x53017c21'u32) # LSR W1,W1,#1.
  builder.words.add(0x51000421'u32) # SUB W1,W1,#1 converts the exact ordinal.
  emitImmediate(builder.words, 2, uint64(jumps))
  builder.words.add(0xeb02003f'u32) # CMP X1,X2; an absent ordinal is a real panic.
  builder.panics.add(conditional(builder.words, 2))
  loadWord(builder.words, 12, 31, 144)
  builder.tableLoads.add(builder.words.len)
  for half in 0..<4:
    builder.words.add((if half == 0: 0xd280000d'u32 else: 0xf280000d'u32) or (uint32(half) shl 21))
  builder.words.add(0x8b0d018d'u32) # ADD X13,X12,X13 points into this immutable image's table.
  builder.words.add(0xd37ef421'u32) # LSL X1,X1,#2.
  builder.words.add(0xb86169ae'u32) # LDR W14,[X13,X1], after complete ordinal preflight.
  builder.words.add(0x710001df'u32) # CMP W14,#0 rejects non-block source targets.
  builder.panics.add(conditional(builder.words, 0))
  builder.words.add(0x8b0e018c'u32) # ADD X12,X12,X14 resolves a checked native code offset.
  builder.words.add(0xd61f0180'u32) # BR X12 remains entirely in this native image.

func conditionCode(opcode: byte): uint32 =
  ## GP comparisons use full64 unsigned/signed bit patterns; no guest flag state is exposed.
  case opcode
  of 81, 170: 0'u32
  of 82, 171: 1'u32
  of 83, 172: 3'u32
  of 84: 9'u32
  of 85, 174: 2'u32
  of 86: 8'u32
  of 87, 173: 11'u32
  of 88: 13'u32
  of 89, 175: 10'u32
  else: 12'u32

proc compileWhole*(source: Program, entry: CodeAddress, image: var WholeImage,
    diagnostic: var string): bool =
  ## Compile every genuine source opcode or reject before publication; gas accounting is explicitly absent.
  assert image.owner.handle == nil
  diagnostic = ""
  var layout = default(Invocation)
  for i in 0..<13: layout.registers[i] = uint64(i+1)
  layout.status = 0x123456789abcdef0'u64
  assert contextSize() == uint32(sizeof(Invocation)) and checkLayout(addr layout) == 1
  let extent = codeLength(source)
  if extent.error != ProgramError.None or extent.value == 0 or extent.value > 4194304'u64:
    diagnostic = "invalid or oversized source"
    return false
  if instruction(source, entry).error != ProgramError.None:
    diagnostic = "invalid entry"
    return false
  var targets: seq[uint64] = @[]
  for ordinal in 0'u64..<1048576'u64:
    let found = jumpTarget(source, JumpIndex(ordinal))
    if found.error == ProgramError.InvalidIndex: break
    if found.error != ProgramError.None:
      diagnostic = "invalid jump table"
      return false
    targets.add(uint64(found.value))
  # A larger logical table is an explicit compilation refusal, never a truncated native target map.
  if jumpTarget(source, JumpIndex(uint64(targets.len))).error != ProgramError.InvalidIndex:
    diagnostic = "jump table exceeds standalone compiler bound"
    return false
  var builder = Builder(words: @[], labels: newSeq[int](int(extent.value)), fixups: @[],
      exits: @[], halts: @[], panics: @[], tableLoads: @[])
  enter(builder)
  builder.fixups.add(Fixup(at: branch(builder.words), pc: uint64(entry)))
  var compiled = 0'u64
  var counts = default(array[256, uint64])
  for pc in 0'u64..<extent.value:
    let decoded = instruction(source, CodeAddress(pc))
    if decoded.error != ProgramError.None: continue # Operand bytes are never compiled as instructions.
    let item = decoded.value
    let slots = instructionRegisters(decoded)
    # The checked executor rejects a local-invalid nonterminator before any register or memory effect.
    if not terminatesBlock(item.opcode) and not instructionHasFallthrough(decoded):
      diagnostic = "missing successor at " & $pc
      return false
    builder.labels[int(pc)] = builder.words.len
    inc compiled
    inc counts[int(item.opcode)]
    if instructionMemoryOperands(decoded).width > 0:
      emitMemory(builder, decoded)
    elif item.opcode in [1'u8, 2]:
      builder.words.add(0xd503201f'u32) # Source fallthrough/unlikely become native fallthrough, with no block callback.
    elif item.opcode == 0:
      fail(builder, pc)
    elif item.opcode in [50'u8, 180]:
      emitDynamic(builder, item, slots, targets.len)
    elif item.opcode == 40 or item.opcode in {80'u8..90'u8, 170'u8..175'u8}:
      let unconditional = item.opcode in [40'u8, 80]
      if item.opcode == 80: emitImmediate(builder.words, reg(slots.aIndex), uint64(item.x))
      if not unconditional:
        let right = if item.opcode <= 90: 1'u32 else: reg(slots.bIndex)
        if item.opcode <= 90: emitImmediate(builder.words, 1, uint64(item.x))
        builder.words.add(0xeb00001f'u32 or (right shl 16) or (reg(slots.aIndex) shl 5))
      if not unconditional and (not instructionTargetStartsBlock(decoded) or
          not instructionHasFallthrough(decoded)):
        # Both successors are part of the accepted conditional contract, regardless of its selected outcome.
        fail(builder, pc)
      elif instructionTargetStartsBlock(decoded):
        let target = if item.displacement < 0: pc-uint64(-item.displacement) else: pc+uint64(
            item.displacement)
        let at = if unconditional: branch(builder.words) else: conditional(builder.words,
            conditionCode(item.opcode))
        builder.fixups.add(Fixup(at: at, pc: target))
      else:
        fail(builder, pc)
    elif not emitOperation(builder.words, item.opcode, slots, uint64(item.x)):
      diagnostic = "unsupported opcode " & $item.opcode & " at " & $pc
      return false
    if not instructionHasFallthrough(decoded) and item.opcode notin {0'u8, 40, 50, 80, 180}:
      fail(builder, pc) # A real missing source successor cannot fall into unrelated generated storage.
    if builder.words.len >= 8000000:
      diagnostic = "native image exceeds32MiB diagnostic bound"
      return false
  finish(builder)
  for fix in builder.fixups:
    if fix.pc >= uint64(builder.labels.len) or builder.labels[int(fix.pc)] == 0:
      diagnostic = "unresolved genuine source target"
      return false
    patchBranch(builder.words, fix.at, builder.labels[int(fix.pc)])
  let tableOffset = uint64(builder.words.len)*4
  for at in builder.tableLoads:
    for half in 0..<4:
      let operation = if half == 0: 0xd280000d'u32 else: 0xf280000d'u32
      builder.words[at+half] = operation or (uint32(half) shl 21) or
          (uint32((tableOffset shr (half*16)) and 65535) shl 5)
  for target in targets:
    let valid = basicBlockStart(source, CodeAddress(target))
    if target < uint64(builder.labels.len) and builder.labels[int(target)] > 0 and
        valid.error == ProgramError.None and valid.value:
      builder.words.add(uint32(builder.labels[int(target)])*4)
    else: builder.words.add(0) # A zero native table offset is an explicit runtime guest panic.
  if builder.words.len == 0 or builder.words.len > 8388608:
    diagnostic = "native image size"
    return false
  let handle = publish(addr builder.words[0], uint(builder.words.len))
  if handle == nil:
    diagnostic = "executable image publication refused"
    return false
  image.owner.handle = handle
  image.source = source
  image.codeBytes = uint64(builder.words.len)*4
  image.instructions = compiled
  image.opcodes = counts
  true


proc allocationCounts*(): array[2, uint64] =
  ## Cold lifecycle evidence comes from this module's same C translation unit, outside guest timing.
  [createdCountNative(), destroyedCountNative()]

proc release*(image: var WholeImage) =
  ## Explicit retirement permits a measured unmap; subsequent automatic destruction is a no-op.
  if image.owner.handle != nil:
    destroyImage(image.owner.handle)
    image.owner.handle = nil
  image.source = default(Program)
