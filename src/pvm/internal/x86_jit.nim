# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Independent Linux x86-64 arithmetic lowering; source charging and every observable boundary stay in the interpreter.
## The SysV leaf borrows one register array in RDI, touches only caller-saved registers and retains no input pointer.
import std/assertions
import ../[program, machine]

proc x86Clock*(): uint64 {.cdecl, importc: "pvm_x86_cpu_ns", header: "x86_memory.h".}
proc createNative(): nil pointer {.cdecl, importc: "pvm_x86_arena_create", header: "x86_memory.h".}
proc destroyNative(handle: nil pointer) {.cdecl, importc: "pvm_x86_arena_destroy",
    header: "x86_memory.h".}
proc publishNative(handle: nil pointer, bytes: pointer, length: uint32): int32 {.cdecl,
    importc: "pvm_x86_arena_publish", header: "x86_memory.h".}
proc callNative(handle: nil pointer, offset: uint32, registers: pointer): cint {.cdecl,
    importc: "pvm_x86_arena_call", header: "x86_memory.h".}

type
  X86Block* = object ## Cold bytecode builder; every operation loads its original sources before writing its destination.
    bytes: seq[byte]
  X86Entry = object ## Only exact source coordinates own callable code offsets; zero is uncompiled and one is refused.
    code, ending, operations: uint32
  X86Arena = object ## Exclusive OS resource; the containing reference never escapes the leased frame/stream.
    handle: nil pointer
  X86Jit* = ref object ## Bounded code-only cache; immutable source identity belongs to its exclusive stream owner.
    arena: X86Arena
    entries: seq[X86Entry]
    unavailable: bool
    fragments*, calls*, operations*, codeBytes*, compilationNs*: uint64

proc `=copy`(destination: var X86Arena, source: X86Arena) {.error.}
proc `=dup`(source: X86Arena): X86Arena {.error.}
proc `=wasMoved`(owner: var X86Arena) {.nodestroy, inline.} =
  ## Moving transfers executable authority; the source must no longer own the native allocation.
  owner.handle = nil

proc `=destroy`(owner: X86Arena) =
  ## A default/moved-from arena has no mapping to retire.
  if owner.handle != nil: destroyNative(owner.handle)

proc newX86Jit*(): X86Jit =
  ## Creation retains no executable allocation until a qualifying source span is actually published.
  X86Jit(arena: X86Arena(handle: nil), entries: @[], unavailable: false)

func supportedX86Opcode*(opcode: byte): bool =
  ## Baseline x86-64 instructions implement these non-exiting scalar operations without optional CPU extensions.
  opcode in {20'u8, 51, 100, 107..110, 131..143, 149..154, 158, 160,
      190..192, 197..202, 207..217, 222..226}

proc put(fragment: var X86Block, bytes: openArray[byte]) =
  ## Every copied byte belongs to the cold builder, never to a source or invocation view.
  for value in bytes: fragment.bytes.add(value)

proc immediate(fragment: var X86Block, operation: byte, value: uint64) =
  ## MOV imm64 defines all bits regardless of sign and previous scratch-register contents.
  put(fragment, [0x48'u8, operation])
  for part in 0..<8: fragment.bytes.add(byte((value shr (part*8)) and 255))

proc readSlot(fragment: var X86Block, slot: range[0..12], right: bool) =
  ## Eight-byte array offsets fit a positive disp8; RDI remains the sole borrowed array base.
  put(fragment, [0x48'u8, 0x8b, (if right: 0x4f'u8 else: 0x47'u8), byte(int(slot)*8)])

proc emitX86Operation*(fragment: var X86Block, opcode: byte, slots: RegisterSlots, value: uint64) =
  ## Scratch RAX/RCX/RDX/R8 obey SysV caller-save rules; all aliases consume their old inputs first.
  assert supportedX86Opcode(opcode)
  if opcode in [20'u8, 51]:
    immediate(fragment, 0xb8, value)
  elif opcode == 100 or opcode in {107'u8..110}:
    readSlot(fragment, slots.aIndex, false)
    case opcode
    of 107: put(fragment, [0x48'u8, 0x0f, 0xbe, 0xc0]) # MOVSX RAX,AL.
    of 108: put(fragment, [0x48'u8, 0x0f, 0xbf, 0xc0]) # MOVSX RAX,AX.
    of 109: put(fragment, [0x0f'u8, 0xb7, 0xc0]) # MOVZX EAX,AX also clears the high word.
    of 110: put(fragment, [0x48'u8, 0x0f, 0xc8]) # BSWAP RAX.
    else: discard # The loaded A value is already the complete move result.
  else:
    if opcode < 190:
      readSlot(fragment, slots.bIndex, false)
      immediate(fragment, 0xb9, value)
    else:
      readSlot(fragment, slots.aIndex, false)
      readSlot(fragment, slots.bIndex, true)
    if opcode in [141'u8, 154]:
      put(fragment, [0x48'u8, 0x91]) # XCHG RAX,RCX makes immediate-minus-B preserve operand order.
    if opcode in {136'u8, 137, 142, 143, 216, 217}:
      let condition = case opcode
        of 136, 216: 0x92'u8 # SETB unsigned less.
        of 137, 217: 0x9c'u8 # SETL signed less.
        of 142: 0x97'u8      # SETA unsigned greater.
        else: 0x9f'u8        # SETG signed greater.
      put(fragment, [0x48'u8, 0x39, 0xc8, 0x0f, condition, 0xc0, 0x0f, 0xb6, 0xc0])
    else:
      case opcode
      of 131, 190: put(fragment, [0x01'u8, 0xc8])
      of 141, 191: put(fragment, [0x29'u8, 0xc8])
      of 135, 192: put(fragment, [0x0f'u8, 0xaf, 0xc1])
      of 138, 197: put(fragment, [0xd3'u8, 0xe0])
      of 139, 198: put(fragment, [0xd3'u8, 0xe8])
      of 140, 199: put(fragment, [0xd3'u8, 0xf8])
      of 160, 223: put(fragment, [0xd3'u8, 0xc8])
      of 132, 210: put(fragment, [0x48'u8, 0x21, 0xc8])
      of 133, 211: put(fragment, [0x48'u8, 0x31, 0xc8])
      of 134, 212: put(fragment, [0x48'u8, 0x09, 0xc8])
      of 154, 201: put(fragment, [0x48'u8, 0x29, 0xc8])
      of 150, 202: put(fragment, [0x48'u8, 0x0f, 0xaf, 0xc1])
      of 151, 207: put(fragment, [0x48'u8, 0xd3, 0xe0])
      of 152, 208: put(fragment, [0x48'u8, 0xd3, 0xe8])
      of 153, 209: put(fragment, [0x48'u8, 0xd3, 0xf8])
      of 158, 222: put(fragment, [0x48'u8, 0xd3, 0xc8])
      of 213, 214, 215:
        if opcode == 215:
          # Mixed signed/unsigned high multiply subtracts sign(A)&B from the unsigned upper product.
          put(fragment, [0x49'u8, 0x89, 0xc0, 0x49, 0xc1, 0xf8, 0x3f, 0x49, 0x21, 0xc8])
        put(fragment, [0x48'u8, 0xf7, (if opcode == 213: 0xe9'u8 else: 0xe1'u8), 0x48, 0x89, 0xd0])
        if opcode == 215: put(fragment, [0x4c'u8, 0x29, 0xc0])
      of 224..226:
        put(fragment, [0x48'u8, 0xf7, 0xd1]) # NOT RCX; these operations explicitly invert the right input.
        put(fragment, [0x48'u8, (if opcode == 224: 0x21'u8 elif opcode ==
            225: 0x09'u8 else: 0x31'u8), 0xc8])
      else: put(fragment, [0x48'u8, 0x01, 0xc8]) # 149/200 full-width wrapping addition.
      if opcode in {131'u8, 135, 138..141, 160, 190..192, 197..199, 223}:
        put(fragment, [0x48'u8, 0x63, 0xc0]) # MOVSXD RAX,EAX restores the GP's signed low-word result.
  put(fragment, [0x48'u8, 0x89, 0x47, byte(int(slots.destinationIndex)*8)])

proc x86Entry*(jit: X86Jit, offset, nodes: uint32): uint32 =
  ## The coordinate map and physical publications have independent finite ceilings.
  if jit.unavailable or nodes > 262144 or offset >= nodes: return 1
  if jit.entries.len < int(nodes): jit.entries.setLen(int(nodes))
  jit.entries[int(offset)].code

proc refuseX86Entry*(jit: X86Jit, offset: uint32) =
  ## A cold refusal is exact to one stream coordinate and never changes another admitted entry.
  if int(offset) < jit.entries.len: jit.entries[int(offset)].code = 1

proc publishX86Entry*(jit: X86Jit, offset, ending, count: uint32, fragment: X86Block): bool =
  ## Only complete bounded pure spans become executable, with no guest pointer encoded in their bytes.
  if jit.unavailable or int(offset) >= jit.entries.len or jit.entries[int(offset)].code != 0:
    return false
  if count < 4 or count > 64 or ending <= offset or ending > uint32(jit.entries.len) or
      jit.fragments >= 1024 or fragment.bytes.len == 0 or fragment.bytes.len >= 4096:
    refuseX86Entry(jit, offset)
    return false
  var bytes = fragment.bytes
  bytes.add(0xc3) # RET is the sole exit; no generated arithmetic operation can suspend or fault.
  if jit.arena.handle == nil:
    when defined(pvmX86JitRefuse): discard # Explicit allocation refusal must exercise canonical fallback.
    else: jit.arena.handle = createNative()
  if jit.arena.handle == nil:
    jit.unavailable = true
    return false
  let code = publishNative(jit.arena.handle, addr bytes[0], uint32(bytes.len))
  if code < 0:
    refuseX86Entry(jit, offset)
    return false
  jit.entries[int(offset)] = X86Entry(code: uint32(code)+2, ending: ending, operations: count)
  inc jit.fragments
  jit.codeBytes = uint64(code)+uint64(bytes.len)
  true

proc callX86Entry*(jit: X86Jit, offset: uint32, registers: var RegisterFile): uint32 =
  ## The frame's original complete reservation authorizes these pure operations; no CPU or memory is retained.
  if int(offset) >= jit.entries.len: return high(uint32)
  let entry = jit.entries[int(offset)]
  if entry.code < 2 or jit.arena.handle == nil: return high(uint32)
  if callNative(jit.arena.handle, entry.code-2, addr registers[0]) == 0: return high(uint32)
  inc jit.calls
  jit.operations += uint64(entry.operations)
  entry.ending
