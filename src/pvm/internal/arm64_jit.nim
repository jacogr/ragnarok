# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Experimental leaf register compiler; checked handler-stream facts are the sole caller authority.
## Generated code borrows only thirteen invocation registers and owns no guest/source pointers.
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

type
  ArmBlock* = object ## A bounded leaf keeps guest registers in X4–X16, loading live-ins and publishing only dirty slots.
    words, terminal: seq[uint32]
    reads, writes: uint32
  ArenaOwner = object ## Move-only OS allocation; the containing reference shares no mutable invocation state.
    handle: nil pointer
  ArmJit* = ref object ## Exclusive frame-owned compiler cache; no executable image escapes its arena owner.
    arena: ArenaOwner
    entries, ends, counts: seq[uint32]
    branchCalls*, headerCalls*: uint64
    fragments*: uint64
    calls*, operations*, codeBytes*, compilationNs*: uint64

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
  ArmJit(arena: ArenaOwner(handle: nil), entries: @[], ends: @[], counts: @[])

func supportedArmOpcode*(opcode: byte): bool =
  ## Non-exiting arithmetic remains independent of guest memory, branch selection and source accounting.
  opcode in {20'u8, 51, 100, 107..110, 131..135, 138..141, 149..154, 158, 160,
      190..192, 197..202, 207..212, 222..226}

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

proc emitArmOperation*(fragment: var ArmBlock, opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  ## Each instruction consumes original operands before declaring its destination; native aliases obey GP ordering.
  assert supportedArmOpcode(opcode)
  if opcode in [20'u8, 51]:
    # Immediate loads have no register live-in; their destination may previously be undefined in the leaf.
    let destination = armWrite(fragment, slots.destinationIndex)
    armImmediate(fragment.words, destination, immediate)
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
    armImmediate(fragment.words, 1, immediate)
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
  let operation = case opcode
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
    armImmediate(fragment.terminal, 1, immediate)
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
  if extent > 262144'u32: return 1
  if jit.entries.len < int(extent):
    jit.entries.setLen(int(extent))
    jit.ends.setLen(int(extent))
    jit.counts.setLen(int(extent))
  jit.entries[int(offset)]

proc refuseArmEntry*(jit: ArmJit, offset: uint32) =
  ## A source-bound refusal avoids repeated compilation attempts without changing interpreted semantics.
  if int(offset) < jit.entries.len and jit.entries[int(offset)] < 2: jit.entries[int(offset)] = 1

proc publishArmEntry*(jit: ArmJit, offset, ending, count: uint32,
    instructions: var seq[uint32]): bool =
  ## Admit at most 1,024 fragments/one MiB; OS or capacity refusal leaves the original interpreter available.
  if jit.fragments >= 1024 or instructions.len == 0 or instructions.len >= 1024:
    refuseArmEntry(jit, offset)
    return false
  if jit.arena.handle == nil: jit.arena.handle = createArena()
  instructions.add(0xd65f03c0'u32) # RET; the leaf never changes SP, LR or any callee-saved register.
  let address = publishArena(jit.arena.handle, addr instructions[0], uint32(instructions.len))
  if address < 0:
    refuseArmEntry(jit, offset)
    return false
  jit.entries[int(offset)] = uint32(address)+2
  jit.ends[int(offset)] = ending
  jit.counts[int(offset)] = count
  inc jit.fragments
  jit.codeBytes+=uint64(instructions.len)*4
  true

proc callArmEntry*(jit: ArmJit, offset: uint32, registers: var RegisterFile): uint32 =
  ## Borrow the current invocation's exact fixed register array; native code cannot access the rest of its frame.
  assert sizeof(RegisterFile) == 104
  let entry = jit.entries[int(offset)]
  assert entry >= 2
  let completed = callArena(jit.arena.handle, entry-2, addr registers)
  assert completed == 1
  inc jit.calls
  jit.operations+=uint64(jit.counts[int(offset)])
  jit.ends[int(offset)]

proc armEnding*(jit: ArmJit, offset: uint32): uint32 =
  ## The original fragment's scalar successor identifies the genuine branch node for deferred capability checks.
  jit.ends[int(offset)]

proc callArmBranch*(jit: ArmJit, offset: uint32, registers: var RegisterFile): uint32 =
  ## Native branches may select only their two captured positive scalar offsets; the checked adapter validates the result extent.
  assert sizeof(RegisterFile) == 104
  let entry = jit.entries[int(offset)]
  assert entry >= 2
  result = nextArena(jit.arena.handle, entry-2, addr registers)
  inc jit.calls
  inc jit.branchCalls
  jit.operations+=uint64(jit.counts[int(offset)])
