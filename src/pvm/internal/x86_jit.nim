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

proc nextNative(handle: nil pointer, offset: uint32, registers: pointer): uint32 {.cdecl,
    importc: "pvm_x86_arena_next", header: "x86_memory.h".}

type
  X86Block* = object ## Cold bytecode builder; every operation loads its original sources before writing its destination.
    bytes: seq[byte]
  X86Entry = object ## Only exact source coordinates own callable code offsets; zero is uncompiled and one is refused.
    code, ending, operations: uint32
    conditional: bool
    probes: uint8 # A cold header gets at most eight discovery visits; exhausted probes restore the hot worker.
  X86RegionCache = object ## One bounded exact-source region, with no mutable invocation address.
    status: uint8
    count: uint32
    code: uint32
    headers, spans, operations: array[2, uint32]
    prices: array[2, uint64]
    calls, blocks: uint64
  X86Arena = object ## Exclusive OS resource; the containing reference never escapes the leased frame/stream.
    handle: nil pointer
  X86Jit* = ref object ## Bounded code-only cache; immutable source identity belongs to its exclusive stream owner.
    arena: X86Arena
    region: X86RegionCache
    entries: seq[X86Entry]
    unavailable: bool
    fragments*, calls*, operations*, codeBytes*, compilationNs*: uint64
    branchCalls*, headerCalls*: uint64

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

proc emitX86Branch*(fragment: var X86Block, opcode: byte, slots: RegisterSlots,
    value: uint64, yes, no: uint32) =
  ## Positive checked stream destinations become immediate scalar results; MOV/CMOV preserve the full-width comparison.
  assert opcode in {81'u8..90, 170..175}
  assert yes < 2147483646'u32 and no < 2147483646'u32
  readSlot(fragment, slots.aIndex, false)
  if opcode <= 90: immediate(fragment, 0xb9, value)
  else: readSlot(fragment, slots.bIndex, true)
  put(fragment, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX consumes both original register/immediate values.
  put(fragment, [0xb8'u8]) # MOV EAX,no leaves comparison flags intact and defines the complete return value.
  for part in 0..<4: fragment.bytes.add(byte((no shr (part*8)) and 255))
  put(fragment, [0xba'u8]) # MOV EDX,yes also preserves flags; RDX is caller-saved.
  for part in 0..<4: fragment.bytes.add(byte((yes shr (part*8)) and 255))
  let condition = case opcode
    of 81, 170: 0x44'u8 # Equal.
    of 82, 171: 0x45'u8 # Not equal.
    of 83, 172: 0x42'u8 # Unsigned below.
    of 84: 0x46'u8      # Unsigned below or equal.
    of 85, 174: 0x43'u8 # Unsigned above or equal.
    of 86: 0x47'u8      # Unsigned above.
    of 87, 173: 0x4c'u8 # Signed less.
    of 88: 0x4e'u8      # Signed less or equal.
    of 89, 175: 0x4d'u8 # Signed greater or equal.
    else: 0x4f'u8       # Signed greater.
  put(fragment, [0x0f'u8, condition, 0xc2]) # CMOVcc EAX,EDX selects a scalar offset, never a host address.

proc x86Ending*(jit: X86Jit, offset: uint32): uint32 =
  ## Only a previously admitted arithmetic record supplies its immutable trailing source coordinate.
  assert int(offset) < jit.entries.len
  jit.entries[int(offset)].ending


proc x86Entry*(jit: X86Jit, offset, nodes: uint32): uint32 =
  ## The coordinate map and physical publications have independent finite ceilings.
  if jit.unavailable or nodes > 262144 or offset >= nodes: return 1
  if jit.entries.len < int(nodes): jit.entries.setLen(int(nodes))
  jit.entries[int(offset)].code

proc refuseX86Entry*(jit: X86Jit, offset: uint32) =
  ## A cold refusal is exact to one stream coordinate and never changes another admitted entry.
  if int(offset) < jit.entries.len and jit.entries[int(offset)].code < 2:
    jit.entries[int(offset)].code = 1

proc publishX86Entry*(jit: X86Jit, offset, ending, count: uint32, fragment: X86Block,
    conditional: bool = false, shortPrefix: bool = false): bool =
  ## Only complete bounded pure spans become executable, with no guest pointer encoded in their bytes.
  if jit.unavailable or int(offset) >= jit.entries.len:
    return false
  let previous = jit.entries[int(offset)]
  if previous.code != 0 and not conditional:
    return false
  if conditional and (previous.code < 2 or previous.conditional or previous.ending != ending or
      count != previous.operations+1): return false
  let minimum = if shortPrefix: 1'u32 else: 4'u32
  if (not conditional and count < minimum) or count > (if conditional: 65'u32 else: 64'u32) or
      ending <= offset or ending > uint32(jit.entries.len) or
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
  jit.entries[int(offset)] = X86Entry(code: uint32(code)+2, ending: ending, operations: count,
      conditional: conditional)
  inc jit.fragments
  jit.codeBytes = uint64(code)+uint64(bytes.len)
  true

proc callX86Entry*(jit: X86Jit, offset: uint32, registers: var RegisterFile): uint32 =
  ## The frame's original complete reservation authorizes these pure operations; no CPU or memory is retained.
  if int(offset) >= jit.entries.len: return high(uint32)
  let entry = jit.entries[int(offset)]
  if entry.code < 2 or entry.conditional or jit.arena.handle == nil: return high(uint32)
  if callNative(jit.arena.handle, entry.code-2, addr registers[0]) == 0: return high(uint32)
  inc jit.calls
  jit.operations += uint64(entry.operations)
  entry.ending


proc callX86Branch*(jit: X86Jit, offset: uint32, registers: var RegisterFile): uint32 =
  ## The exclusive source record selects only its two checked scalar destinations; invocation registers are borrowed afresh.
  assert int(offset) < jit.entries.len
  let entry = jit.entries[int(offset)]
  assert entry.code >= 2 and entry.conditional and jit.arena.handle != nil
  result = nextNative(jit.arena.handle, entry.code-2, addr registers[0])
  if result == high(uint32): return
  inc jit.calls
  inc jit.branchCalls
  jit.operations += uint64(entry.operations)


type
  X86RegionBlock* = object ## Captured pure source block and its already-checked scalar successors.
    header*, span*, operations*, yes*, no*: uint32
    price*: uint64
    body*: X86Block
  X86RegionFixup = object ## Bounded rel32 branch, distinguishing guard exits from native successors.
    at: int
    target: uint32
    guard: bool

func x86RegionStatus*(jit: X86Jit): uint8 =
  ## Global capacity/storage refusal never retries; local candidate negatives retain bounded header probes.
  jit.region.status

proc x86StartProbe*(jit: X86Jit, header: uint32) =
  ## Header coordinates share the existing bounded entry table without enlarging hot records.
  assert int(header) < jit.entries.len
  jit.entries[int(header)].probes = 8

proc x86FinishProbe*(jit: X86Jit, header: uint32): bool =
  ## Exhaustion removes discovery from subsequent ordinary block visits.
  assert int(header) < jit.entries.len
  if jit.entries[int(header)].probes > 0: dec jit.entries[int(header)].probes
  jit.entries[int(header)].probes == 0

func x86RegionCount*(jit: X86Jit): range[1..2] =
  ## Only published proof records expose active block coordinates.
  let count = jit.region.count
  assert jit.region.status == 2 and count >= 1 and count <= 2
  range[1..2](count)

func x86RegionHeader*(jit: X86Jit, index: range[0..1]): uint32 =
  ## The region retains exact-source headers rather than host-code addresses.
  assert jit.region.status == 2 and uint32(index) < jit.region.count
  jit.region.headers[index]

func x86RegionMatches*(jit: X86Jit, headers, spans: array[2, uint32],
    prices: array[2, uint64]): bool =
  ## Every fresh invocation must match the captured charge context, including inactive zero slots.
  jit.region.status == 2 and jit.region.headers == headers and jit.region.spans == spans and
      jit.region.prices == prices

proc regionWord(fragment: var X86Block, value: uint32) =
  ## Emit a complete little-endian rel32/immediate without native host-endian assumptions.
  for shift in 0..<4: fragment.bytes.add(byte((value shr (shift*8)) and 255))

proc regionEdge(fragment: var X86Block, fixes: var seq[X86RegionFixup], target: uint32,
    condition: byte, guard: bool) =
  ## Conditional and unconditional edges reserve four displacement bytes for bounded relocation.
  if condition == 0: put(fragment, [0xe9'u8])
  else: put(fragment, [0x0f'u8, condition])
  fixes.add(X86RegionFixup(at: fragment.bytes.len, target: target, guard: guard))
  regionWord(fragment, 0)

proc publishX86Region*(jit: X86Jit, blocks: array[2, X86RegionBlock], count: range[1..2]): bool =
  ## One observed pure loop uses caller-saved R9/R10 for gas/quota; ordinary operations still access their register array.
  assert jit.region.status == 0
  var code = default(X86Block)
  # RDI is the borrowed register array, RSI the fresh five-word context; bodies touch only RAX/RCX/RDX/R8.
  put(code, [0x4c'u8, 0x8b, 0x0e, 0x4c, 0x8b, 0x56, 8])
  var labels = default(array[2, int])
  var fixes: seq[X86RegionFixup] = @[]
  for index in 0..<count:
    let item = blocks[index]
    if item.header >= 262144 or item.span < 2 or item.span > 65 or
        item.operations != item.span or item.body.bytes.len < 16: return false
    let terminal = item.body.bytes.len
    # Only the existing emitter's MOV/MOV/CMOV scalar-selection tail can be replaced by native edges.
    if item.body.bytes[terminal-13] != 0xb8 or item.body.bytes[terminal-8] != 0xba or
        item.body.bytes[terminal-3] != 0x0f or item.body.bytes[terminal-1] != 0xc2: return false
    let condition = item.body.bytes[terminal-2]
    if condition notin {0x42'u8..0x47, 0x4c..0x4f}: return false
    labels[index] = code.bytes.len
    put(code, [0x49'u8, 0x81, 0xfa]) # CMP R10,wholeSourceSpan; partial blocks return before debit.
    regionWord(code, item.span)
    regionEdge(code, fixes, item.header, 0x82, true)
    immediate(code, 0xb8, item.price)
    put(code, [0x49'u8, 0x39, 0xc1]) # CMP R9,RAX is an unsigned full64 gas guard.
    regionEdge(code, fixes, item.header, 0x82, true)
    put(code, [0x49'u8, 0x29, 0xc1, 0x49, 0x81, 0xea])
    regionWord(code, item.span)
    # Invocation-local visits and last completed header preserve counters and exact reservation endpoint on every exit.
    put(code, [0x48'u8, 0xff, 0x46, byte(16+index*8), 0x48, 0xc7, 0x46, 32])
    regionWord(code, item.header)
    for position in 0..<terminal-13: code.bytes.add(item.body.bytes[position])
    regionEdge(code, fixes, item.yes, condition+0x40'u8, false)
    regionEdge(code, fixes, item.no, 0, false)
  var exits: seq[uint32] = @[]
  var exitLabels: seq[int] = @[]
  for fix in fixes:
    var internal = false
    if not fix.guard:
      for index in 0..<count:
        if blocks[index].header == fix.target: internal = true
    if internal: continue
    var known = false
    for target in exits:
      if target == fix.target: known = true
    if not known: exits.add(fix.target)
  var returns: seq[int] = @[]
  for target in exits:
    exitLabels.add(code.bytes.len)
    put(code, [0xb8'u8])
    regionWord(code, target)
    put(code, [0xe9'u8])
    returns.add(code.bytes.len)
    regionWord(code, 0)
  let epilogue = code.bytes.len
  put(code, [0x4c'u8, 0x89, 0x0e, 0x4c, 0x89, 0x56, 8, 0xc3])
  if code.bytes.len >= 4096: return false
  if jit.fragments >= 1024:
    # Exhausted owner-wide publication capacity is permanent, unlike this candidate's shape or size.
    jit.region.status = 1
    return false
  for at in returns:
    let relative = uint32(epilogue-at-4)
    for shift in 0..<4: code.bytes[at+shift] = byte((relative shr (shift*8)) and 255)
  for fix in fixes:
    var target = -1
    if not fix.guard:
      for index in 0..<count:
        if blocks[index].header == fix.target: target = labels[index]
    if target < 0:
      for index in 0..<exits.len:
        if exits[index] == fix.target: target = exitLabels[index]
    assert target >= 0 and target < code.bytes.len
    let origin = fix.at+4
    let relative = if target >= origin: uint32(target-origin) else: 0'u32-uint32(origin-target)
    for shift in 0..<4: code.bytes[fix.at+shift] = byte((relative shr (shift*8)) and 255)
  # Only proven owner-wide capacity/storage failure is sticky; local negatives exhaust existing per-header probes.
  jit.region.status = 1
  if jit.arena.handle == nil: return false
  let published = publishNative(jit.arena.handle, addr code.bytes[0], uint32(code.bytes.len))
  if published < 0: return false
  jit.region.code = uint32(published)
  for index in 0..<count:
    jit.region.headers[index] = blocks[index].header
    jit.region.spans[index] = blocks[index].span
    jit.region.prices[index] = blocks[index].price
    jit.region.operations[index] = blocks[index].operations
  jit.region.count = uint32(count)
  jit.region.status = 2
  inc jit.fragments
  jit.codeBytes = uint64(published)+uint64(code.bytes.len)
  true

proc regionNative(handle: nil pointer, offset: uint32, registers, state: pointer): uint32
    {.cdecl, importc: "pvm_x86_arena_region", header: "x86_memory.h".}

proc callX86Region*(jit: X86Jit, registers: var RegisterFile, state: var array[5, uint64]): uint32 =
  ## Fresh register/context borrows expire on return; visit accounting is bounded by consumed source attempts.
  assert jit.region.status == 2 and state[2] == 0 and state[3] == 0
  let available = state[1]
  let gas = state[0]
  result = regionNative(jit.arena.handle, jit.region.code, addr registers, addr state)
  assert state[1] <= available and state[0] <= gas
  let consumed = available-state[1]
  var accounted = 0'u64
  for index in 0..<x86RegionCount(jit):
    let span = uint64(jit.region.spans[index])
    let count = state[index+2]
    assert count <= consumed div span
    let attempts = count*span
    assert accounted <= consumed and attempts <= consumed-accounted
    accounted += attempts
    jit.operations += count*uint64(jit.region.operations[index])
    jit.region.blocks += count
  assert accounted == consumed
  inc jit.calls
  inc jit.branchCalls
  inc jit.headerCalls
  inc jit.region.calls

func x86RegionStatistics*(jit: X86Jit): array[2, uint64] =
  ## Distinguish connected entries from completed logical blocks without claiming hardware instruction counts.
  [jit.region.calls, jit.region.blocks]
