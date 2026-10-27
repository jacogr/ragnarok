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

type
  ArenaOwner = object ## Move-only OS allocation; the containing reference shares no mutable invocation state.
    handle: nil pointer
  ArmJit* = ref object ## Exclusive frame-owned compiler cache; no executable image escapes its arena owner.
    arena: ArenaOwner
    entries, ends, counts: seq[uint32]
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
  ## This initial slice lowers modular 64-bit add/subtract and full-width immediate bitwise operations.
  opcode in [132'u8, 133, 134, 149, 200, 201]

proc emitArmOperation*(words: var seq[uint32], opcode: byte, slots: RegisterSlots,
    immediate: uint64) =
  ## Every register coordinate is a genuine decoder-saturated slot; leaf code uses only volatile X0–X3.
  assert supportedArmOpcode(opcode)
  let left = if opcode in [200'u8, 201]: slots.aIndex else: slots.bIndex
  words.add(0xf9400001'u32 or (uint32(left) shl 10)) # LDR X1,[X0,#left*8]
  if opcode in [200'u8, 201]:
    # Read both original operands before storing, including destination/source aliases.
    words.add(0xf9400002'u32 or (uint32(slots.bIndex) shl 10))
  else:
    # Four bounded halfwords materialize the exact unsigned immediate, including sign-extended values.
    words.add(0xd2800002'u32 or (uint32(immediate and 65535) shl 5))
    for half in 1..3:
      words.add(0xf2800002'u32 or (uint32(half) shl 21) or
          (uint32((immediate shr (half*16)) and 65535) shl 5))
  let operation = case opcode
    of 132: 0x8a020023'u32 # AND X3,X1,X2
    of 133: 0xca020023'u32 # EOR X3,X1,X2
    of 134: 0xaa020023'u32 # ORR X3,X1,X2
    of 201: 0xcb020023'u32 # SUB X3,X1,X2, modulo 2^64
    else: 0x8b020023'u32   # ADD X3,X1,X2, modulo 2^64
  words.add(operation)
  words.add(0xf9000003'u32 or (uint32(slots.destinationIndex) shl 10))

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
  if int(offset) < jit.entries.len: jit.entries[int(offset)] = 1

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
