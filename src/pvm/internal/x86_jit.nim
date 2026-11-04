# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Independent Linux x86-64 arithmetic lowering; source charging and every observable boundary stay in the interpreter.
## The SysV leaf borrows one register array in RDI, touches only caller-saved registers and retains no input pointer.
import std/assertions
import ../[program, machine]
import ./jit_rules

proc x86Clock*(): uint64 {.cdecl, importc: "pvm_x86_cpu_ns", header: "x86_memory.h".}
  ## Read the native CPU-time counter used to measure x86 JIT work.

proc createNative(): nil pointer {.cdecl, importc: "pvm_x86_arena_create", header: "x86_memory.h".}
  ## Allocate one native executable arena, returning nil when allocation is unavailable.

proc destroyNative(handle: nil pointer) {.cdecl, importc: "pvm_x86_arena_destroy",
    header: "x86_memory.h".}
  ## Release the native arena and its executable-memory ownership.

proc publishNative(handle: nil pointer, bytes: pointer, length: uint32): int32 {.cdecl,
    importc: "pvm_x86_arena_publish", header: "x86_memory.h".}
  ## Publish the supplied machine-code bytes through the native arena permission boundary.

proc callNative(handle: nil pointer, offset: uint32, registers: pointer): cint {.cdecl,
    importc: "pvm_x86_arena_call", header: "x86_memory.h".}
  ## Execute a published entry with a borrowed register file and return its native status.

proc nextNative(handle: nil pointer, offset: uint32, registers: pointer): uint32 {.cdecl,
    importc: "pvm_x86_arena_next", header: "x86_memory.h".}
  ## Execute an entry and return its next control-flow offset without retaining registers.

when defined(pvmX86Jit) or defined(pvmX86MemoryCycleSeal):
  type
    X86MemoryCycleHandlerKind* {.pure.} = enum
      ## Only copied identity classes are retained; a callable handler pointer never escapes.
      Other, Ordinary, CheckedWord, NativeWhole, NativeProbe, NativeRegion
    X86MemoryCycleHeader* = object
      ## Copied source and cached-arm coordinates contain no invocation pointer or guest value.
      pc*, header*, ordinal*, span*, terminal*, yes*, no*: uint32
      price*: uint64
      opcode*: byte
      kind*: X86MemoryCycleHandlerKind
    X86MemoryCycleCandidate* = object
      ## One exact source graph and its proved roles remain separate from callable pure regions.
      prefix*, dirty*, tail*, outside*: X86MemoryCycleHeader
      readOrdinal*: uint32
      readImmediate*, storeDisplacement*, initialShift*: uint64
      readOpcode*, readWidth*: byte
      data*, shift*, extracted*, base*, bound*, length*, counter*,
        readResult*: byte
    X86WideCycleCandidate* = object
      ## Copied seven-block source graph; no guest value, mutable frame or diagnostic PC is retained.
      cycle*: X86MemoryCycleCandidate
      loopGuard*, loopBranch*, readBlock*, rare*: X86MemoryCycleHeader
      readOperations*, readLoads*: uint32
    X86MemoryCycleSlot = object
      ## One published code offset binds copied source facts to an exclusively leased plan owner.
      candidate: X86MemoryCycleCandidate
      planIdentity: nil pointer
      code: uint32
      active: bool
    X86MemoryCycleCandidateCache = object
      ## Eight cold candidate slots cannot overwrite or evict the independent pure-region cache.
      count: uint8
      entries: array[8, X86MemoryCycleSlot]
      calls, groups, tails: uint64

  when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
    type X86WideCycleCache = object
      ## One private source-bound wider image owns no frame or invocation pointer.
      status: uint8
      candidate: X86WideCycleCandidate
      planIdentity: nil pointer
      code, childCode: uint32
      calls, readRefusals: uint64
      when defined(pvmX86WideParentRefusalWitness):
        refuseParentOnce: bool

when defined(pvmX86Jit) or (defined(pvmX86MemoryCycleNativeProof) and
    defined(pvmX86MemoryCycleSeal)):
  type
    X86CycleMemory* = object
      ## Current invocation's clipped private byte descriptors match pvm_x86_cycle_memory exactly.
      readPtr*: nil pointer
      readFirst*, readEnd*: uint64
      writePtr*: nil pointer
      writeFirst*, writeEnd*: uint64
      dirtyWords*, reserved*: uint32
    X86CycleState* = object
      ## Native completion ledger matches pvm_x86_cycle_state; no output is trusted before validation.
      gas*, attempts*: uint64
      visits*: array[3, uint64]
      wordGroups*: uint64
      lastCompleted*, exitKind*: uint32
      reserved*: uint64
    X86CycleEmission* = object
      ## Original sealed operand slots let the existing arithmetic and comparison emitter be reused.
      prefixLoad*, prefixBound*, prefixStep*, dirtyBranch*: RegisterSlots
      tailStep*, tailBranch*: RegisterSlots

  when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
    type
      X86WideOperation* = object
        ## Copied immutable source operands drive cold wide-body emission.
        opcode*: byte
        slots*: RegisterSlots
        immediate*: uint64
      X86WideEmission* = object
        ## The source seal bounds every copied operation before one image is built.
        prefix*: X86CycleEmission
        guardOperations*: array[2, X86WideOperation]
        guardBranch*, loopBranch*: RegisterSlots
        guardImmediate*, loopImmediate*: uint64
        readOperations*: array[64, X86WideOperation]
        readCount*: uint32
      X86WideReadRegion* = object
        ## One clipped private readable extent; no pointer survives the native invocation.
        data*: nil pointer
        first*, ending*: uint64
      X86WideMemory* = object
        ## The narrow child's first 56 bytes retain its C ABI; three fresh regions follow.
        cycle*: X86CycleMemory
        regions*: array[3, X86WideReadRegion]
      X86WideState* = object
        ## The narrow child's first 64 bytes retain its receipt ABI; four outer visit lanes follow.
        cycle*: X86CycleState
        outerVisits*: array[4, uint64]
        childCalls*: uint64

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
    when defined(pvmX86Jit) or defined(pvmX86MemoryCycleSeal):
      memoryCycle: X86MemoryCycleCandidateCache
      when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
        wideCycle: X86WideCycleCache
    entries: seq[X86Entry]
    unavailable: bool
    fragments*, calls*, operations*, codeBytes*, compilationNs*: uint64
    branchCalls*, headerCalls*: uint64

const
  x86NonRegionFragmentLimit = 8191'u64 ## Leave one owner slot for the pure region.
  x86TotalFragmentLimit = 8192'u64     ## Leaves and the one-shot region share this publication budget.

func x86PublicationAvailable(jit: X86Jit, region = false): bool =
  ## Nonregion entries, including this cycle, leave one shared owner slot for the pure region.
  jit.fragments < (if region: x86TotalFragmentLimit else: x86NonRegionFragmentLimit)

proc `=copy`(destination: var X86Arena, source: X86Arena) {.error.}
  ## Reject copying the exclusive native executable arena owner.

proc `=dup`(source: X86Arena): X86Arena {.error.}
  ## Reject duplication of the exclusive native executable arena owner.

proc `=wasMoved`(owner: var X86Arena) {.nodestroy, inline.} =
  ## Moving transfers executable authority; the source must no longer own the native allocation.
  owner.handle = nil

proc `=destroy`(owner: X86Arena) =
  ## A default/moved-from arena has no mapping to retire.
  if owner.handle != nil: destroyNative(owner.handle)

proc newX86Jit*(): X86Jit =
  ## Creation retains no executable allocation until a qualifying source span is actually published.
  X86Jit(arena: X86Arena(handle: nil), entries: @[], unavailable: false)

func supportedX86Opcode*(opcode: byte): bool {.inline.} =
  ## Baseline x86-64 instructions implement these non-exiting scalar operations without optional CPU extensions.
  supportedScalarOpcode(opcode)

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
  if (not conditional and count < minimum) or count > (
      if conditional: 65'u32 else: 64'u32) or ending <= offset or ending > uint32(
          jit.entries.len) or
      not x86PublicationAvailable(jit) or fragment.bytes.len == 0 or
      fragment.bytes.len >= 4096:
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
  if not x86PublicationAvailable(jit, region = true):
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
  ## Execute a published region with borrowed registers and region accounting state.

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

when defined(pvmX86Jit) or (defined(pvmX86MemoryCycleNativeProof) and
    defined(pvmX86MemoryCycleSeal)):
  type X86CycleFixup = object
    ## A local signed rel32 patch names one label in the complete unpublished image.
    at: int
    target: uint8

  const
    cycleDirty = 0'u8
    cycleTail = 1'u8
    cyclePrefix = 2'u8
    cycleGuardDirty = 3'u8
    cycleGuardTail = 4'u8
    cycleGuardPrefix = 5'u8
    cycleOutside = 6'u8
    cycleEpilogue = 7'u8

  proc cycleWord(code: var X86Block, value: uint32) =
    ## Encode a fixed little-endian scalar without host pointers or native byte-order assumptions.
    for shift in 0..<4: code.bytes.add(byte((value shr (shift*8)) and 255))

  proc cycleQword(code: var X86Block, value: uint64) =
    ## All original gas prices and displacements retain their full unsigned 64-bit value.
    for shift in 0..<8: code.bytes.add(byte((value shr (shift*8)) and 255))

  proc cycleEdge(code: var X86Block, fixes: var seq[X86CycleFixup], condition,
      target: uint8) =
    ## A zero condition is JMP; otherwise an unsigned/signed Jcc owns exactly one rel32 field.
    if condition == 0: put(code, [0xe9'u8])
    else: put(code, [0x0f'u8, condition])
    fixes.add(X86CycleFixup(at: code.bytes.len, target: target))
    cycleWord(code, 0)

  proc cycleBudget(code: var X86Block, fixes: var seq[X86CycleFixup],
      price: uint64, span: byte, guard: uint8) =
    ## Match zero-budget, unpaid gas and full-span precedence without touching current-block state.
    put(code, [0x49'u8, 0x83, 0x7f, 0x08, 0x00]) # CMP state.attempts,0.
    cycleEdge(code, fixes, 0x84, guard)
    put(code, [0x48'u8, 0xb8]) # MOV RAX,original price.
    cycleQword(code, price)
    put(code, [0x49'u8, 0x39, 0x07]) # CMP state.gas,RAX.
    cycleEdge(code, fixes, 0x82, guard)
    put(code, [0x49'u8, 0x83, 0x7f, 0x08, span]) # CMP state.attempts,span.
    cycleEdge(code, fixes, 0x82, guard)

  proc cycleDebit(code: var X86Block, price: uint64, span: byte) =
    ## Debit only after every current-header memory proof has succeeded.
    put(code, [0x48'u8, 0xb8])
    cycleQword(code, price)
    put(code, [0x49'u8, 0x29, 0x07]) # SUB state.gas,RAX.
    put(code, [0x49'u8, 0x83, 0x6f, 0x08, span]) # SUB state.attempts,span.

  proc cycleComplete(code: var X86Block, visitOffset, visits: byte,
      header: uint32, group: bool) =
    ## Publish a completion only after all guest effects and the selected branch have finished.
    put(code, [0x49'u8, 0x83, 0x47, visitOffset, visits])
    if group: put(code, [0x49'u8, 0xff, 0x47, 0x28])
    put(code, [0x41'u8, 0xc7, 0x47, 0x30])
    cycleWord(code, header)

  proc cycleReturn(code: var X86Block, fixes: var seq[X86CycleFixup],
      kind: uint32, header: uint32) =
    ## Return a scalar stream coordinate and an explicit guard/external receipt through one epilogue.
    put(code, [0x41'u8, 0xc7, 0x47, 0x34]) # MOV state.exitKind,kind.
    cycleWord(code, kind)
    put(code, [0xb8'u8]) # MOV EAX,header.
    cycleWord(code, header)
    cycleEdge(code, fixes, 0, cycleEpilogue)

  proc buildX86MemoryCycleImage*(candidate: X86MemoryCycleCandidate,
      operands: X86CycleEmission, image: var seq[byte]): bool =
    ## Build one bounded dirty→tail→prefix loop with all guards and exits local to a single image.
    image = @[]
    if candidate.prefix.header >= 262144 or candidate.dirty.header >= 262144 or
        candidate.tail.header >= 262144 or candidate.outside.header >= 262144 or
        candidate.prefix.span == 0 or candidate.prefix.span > 65 or
        candidate.dirty.span != 5 or candidate.tail.span == 0 or
            candidate.tail.span > 65 or
        candidate.dirty.price > high(uint64) div 4 or
        candidate.data > 12 or candidate.shift > 12 or candidate.extracted >
            12 or
        candidate.base > 12 or candidate.bound > 12 or candidate.length > 12 or
        candidate.counter > 12 or candidate.readResult > 12 or
        candidate.readOpcode notin {52'u8..58}:
      return false
    let expectedWidth: byte = case candidate.readOpcode
      of 52, 53: 1'u8
      of 54, 55: 2'u8
      of 56, 57: 4'u8
      else: 8'u8
    if candidate.readWidth != expectedWidth: return false
    let readAddress = uint32(candidate.readImmediate and 0xffffffff'u64)
    if readAddress < 65536 or uint64(readAddress) >
        uint64(high(uint32))-uint64(candidate.readWidth): return false
    var code = default(X86Block)
    var labels = default(array[8, int])
    for index in 0..<labels.len: labels[index] = -1
    var fixes: seq[X86CycleFixup] = @[]
    # Every call-local pointer lives in a preserved register; all return stubs share the matching pops.
    put(code, [0x41'u8, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57,
      0x49, 0x89, 0xfc, 0x49, 0x89, 0xf5, 0x49, 0x89, 0xd6, 0x49, 0x89, 0xcf])

    labels[int(cycleDirty)] = code.bytes.len
    cycleBudget(code, fixes, candidate.dirty.price*4, 20, cycleGuardDirty)
    # The checked word projection requires shift alignment and nonwrapping base+4 <= bound.
    put(code, [0x49'u8, 0x8b, 0x44, 0x24, byte(int(candidate.shift)*8),
      0xa9, 0x1f, 0, 0, 0]) # MOV shift; TEST EAX,31.
    cycleEdge(code, fixes, 0x85, cycleGuardDirty)
    put(code, [0x49'u8, 0x8b, 0x4c, 0x24, byte(int(candidate.base)*8), 0x48, 0xba])
    cycleQword(code, high(uint64)-4)
    put(code, [0x48'u8, 0x39, 0xd1]) # CMP base,UINT64_MAX-4.
    cycleEdge(code, fixes, 0x87, cycleGuardDirty)
    put(code, [0x48'u8, 0x8d, 0x41, 0x04,
      0x49, 0x8b, 0x54, 0x24, byte(int(candidate.bound)*8),
      0x48, 0x39, 0xd0]) # CMP base+4,bound.
    cycleEdge(code, fixes, 0x87, cycleGuardDirty)
    put(code, [0x48'u8, 0xb8])
    cycleQword(code, candidate.storeDisplacement)
    # ADD wraps at 64 bits before MOV EAX clips to 32; the low 32 bits equal the source address equation.
    put(code, [0x48'u8, 0x01, 0xc8, 0x89, 0xc0, 0x49, 0x89, 0xc1])
    # R9 is the clipped 32-bit guest address; all following pointer arithmetic uses this proven value.
    put(code, [0x49'u8, 0x81, 0xf9])
    cycleWord(code, 65536)
    cycleEdge(code, fixes, 0x82, cycleGuardDirty)
    put(code, [0xba'u8])
    cycleWord(code, high(uint32)-4)
    put(code, [0x49'u8, 0x39, 0xd1])
    cycleEdge(code, fixes, 0x87, cycleGuardDirty)
    put(code, [0x44'u8, 0x89, 0xca, 0x81, 0xe2, 0xff, 0x0f, 0, 0,
      0x81, 0xfa, 0xfc, 0x0f, 0, 0]) # Same-page four-byte store.
    cycleEdge(code, fixes, 0x87, cycleGuardDirty)
    put(code, [0x49'u8, 0x8b, 0x55, 0x20, 0x49, 0x39, 0xd1])
    cycleEdge(code, fixes, 0x82, cycleGuardDirty)
    put(code, [0x49'u8, 0x8b, 0x55, 0x28, 0x49, 0x8d, 0x41, 0x04,
      0x48, 0x39, 0xd0])
    cycleEdge(code, fixes, 0x87, cycleGuardDirty)
    # flatMarkStore indexes the bitmap by guest page, then 64-page word and low-six-bit mask.
    put(code, [0x44'u8, 0x89, 0xca, 0xc1, 0xea, 0x0c, 0x89, 0xd0,
      0xc1, 0xe8, 0x06, 0x41, 0x3b, 0x45, 0x30])
    cycleEdge(code, fixes, 0x83, cycleGuardDirty)
    put(code, [0x4d'u8, 0x8b, 0x14, 0xc6, 0x89, 0xd1, 0x83, 0xe1, 0x3f,
      0x41, 0xbb, 1, 0, 0, 0, 0x49, 0xd3, 0xe3, 0x4d, 0x85, 0xda])
    cycleEdge(code, fixes, 0x84, cycleGuardDirty)
    cycleDebit(code, candidate.dirty.price*4, 20)
    put(code, [0x4d'u8, 0x8b, 0x55, 0x18, 0x49, 0x8b, 0x45, 0x20,
      0x49, 0x29, 0xc1, 0x41, 0x8b, 0x44, 0x24, byte(int(candidate.data)*8),
      0x43, 0x89, 0x04, 0x0a, 0xc1, 0xe8, 0x18,
      0x49, 0x89, 0x44, 0x24, byte(int(candidate.extracted)*8),
      0x49, 0x83, 0x44, 0x24, byte(int(candidate.base)*8), 4,
      0x49, 0x83, 0x44, 0x24, byte(int(candidate.shift)*8), 32])
    put(code, [0x4c'u8, 0x89, 0xe7]) # Existing branch emitter reads registers through RDI.
    emitX86Branch(code, 171, operands.dirtyBranch, 0, candidate.dirty.header,
      candidate.tail.header)
    cycleComplete(code, 24, 4, candidate.dirty.header, true)
    put(code, [0x3d'u8])
    cycleWord(code, candidate.dirty.header)
    cycleEdge(code, fixes, 0x84, cycleDirty)
    cycleEdge(code, fixes, 0, cycleTail)

    labels[int(cycleTail)] = code.bytes.len
    cycleBudget(code, fixes, candidate.tail.price, byte(candidate.tail.span), cycleGuardTail)
    put(code, [0x41'u8, 0xb9])
    cycleWord(code, readAddress)
    put(code, [0x49'u8, 0x8b, 0x55, 0x08, 0x49, 0x39, 0xd1])
    cycleEdge(code, fixes, 0x82, cycleGuardTail)
    put(code, [0x49'u8, 0x8b, 0x55, 0x10,
      0x49, 0x8d, 0x41, candidate.readWidth, 0x48, 0x39, 0xd0])
    cycleEdge(code, fixes, 0x87, cycleGuardTail)
    cycleDebit(code, candidate.tail.price, byte(candidate.tail.span))
    put(code, [0x4d'u8, 0x8b, 0x55, 0x00, 0x49, 0x8b, 0x45, 0x08, 0x49, 0x29, 0xc1])
    case candidate.readOpcode
    of 52: put(code, [0x43'u8, 0x0f, 0xb6, 0x04, 0x0a])
    of 53: put(code, [0x4b'u8, 0x0f, 0xbe, 0x04, 0x0a])
    of 54: put(code, [0x43'u8, 0x0f, 0xb7, 0x04, 0x0a])
    of 55: put(code, [0x4b'u8, 0x0f, 0xbf, 0x04, 0x0a])
    of 56: put(code, [0x43'u8, 0x8b, 0x04, 0x0a])
    of 57: put(code, [0x4b'u8, 0x63, 0x04, 0x0a])
    of 58: put(code, [0x4b'u8, 0x8b, 0x04, 0x0a])
    else: return false
    put(code, [0x49'u8, 0x89, 0x44, 0x24, byte(int(candidate.readResult)*8),
      0x4c, 0x89, 0xe7])
    emitX86Operation(code, 131, operands.tailStep, 1)
    emitX86Branch(code, 173, operands.tailBranch, 0, candidate.prefix.header,
      candidate.outside.header)
    cycleComplete(code, 32, 1, candidate.tail.header, false)
    put(code, [0x3d'u8])
    cycleWord(code, candidate.prefix.header)
    cycleEdge(code, fixes, 0x84, cyclePrefix)
    cycleEdge(code, fixes, 0, cycleOutside)

    labels[int(cyclePrefix)] = code.bytes.len
    cycleBudget(code, fixes, candidate.prefix.price, byte(
        candidate.prefix.span),
      cycleGuardPrefix)
    cycleDebit(code, candidate.prefix.price, byte(candidate.prefix.span))
    put(code, [0x4c'u8, 0x89, 0xe7])
    emitX86Operation(code, 51, operands.prefixLoad, candidate.initialShift)
    emitX86Operation(code, 200, operands.prefixBound, 0)
    emitX86Operation(code, 149, operands.prefixStep, 1)
    cycleComplete(code, 16, 1, candidate.prefix.header, false)
    cycleEdge(code, fixes, 0, cycleDirty)

    labels[int(cycleGuardDirty)] = code.bytes.len
    cycleReturn(code, fixes, 1, candidate.dirty.header)
    labels[int(cycleGuardTail)] = code.bytes.len
    cycleReturn(code, fixes, 1, candidate.tail.header)
    labels[int(cycleGuardPrefix)] = code.bytes.len
    cycleReturn(code, fixes, 1, candidate.prefix.header)
    labels[int(cycleOutside)] = code.bytes.len
    cycleReturn(code, fixes, 2, candidate.outside.header)
    labels[int(cycleEpilogue)] = code.bytes.len
    put(code, [0x41'u8, 0x5f, 0x41, 0x5e, 0x41, 0x5d, 0x41, 0x5c, 0xc3])
    if code.bytes.len == 0 or code.bytes.len > 4096: return false
    for fix in fixes:
      if int(fix.target) >= labels.len or labels[int(fix.target)] <
          0: return false
      let delta = int64(labels[int(fix.target)])-int64(fix.at+4)
      if delta < -2147483648'i64 or delta > 2147483647'i64: return false
      let encoded = cast[uint32](int32(delta))
      for shift in 0..<4:
        code.bytes[fix.at+shift] = byte((encoded shr (shift*8)) and 255)
    image = move(code.bytes)
    true

  proc cycleNative(handle: nil pointer, offset: uint32, registers: pointer,
      memory, dirty, state: nil pointer): uint64
      {.cdecl, importc: "pvm_x86_arena_cycle", header: "x86_memory.h".}
    ## The high return word proves whether the typed C boundary invoked any generated bytes.

  func x86CycleSlot*(jit: X86Jit, dirty: uint32): int =
    ## A bounded scalar lookup never exposes a native entry or source pointer to the caller.
    if jit == nil: return -1
    for index in 0..<int(jit.memoryCycle.count):
      if jit.memoryCycle.entries[index].active and
          jit.memoryCycle.entries[index].candidate.dirty.header ==
              dirty: return index
    -1

  func x86CycleCandidate*(jit: X86Jit, index: int): X86MemoryCycleCandidate =
    ## Only an active slot yields its copied source graph.
    assert jit != nil and index >= 0 and index < int(jit.memoryCycle.count)
    assert jit.memoryCycle.entries[index].active
    jit.memoryCycle.entries[index].candidate

  func x86CycleBound*(jit: X86Jit, index: int,
      planIdentity: nil pointer): bool =
    ## Same-plan restoration may move the owner; the immutable plan identity must still match.
    jit != nil and index >= 0 and index < int(jit.memoryCycle.count) and
      jit.memoryCycle.entries[index].active and planIdentity != nil and
      jit.memoryCycle.entries[index].planIdentity == planIdentity

  proc retireX86Cycle*(jit: X86Jit, index: int) =
    ## Revocation only disables this optimization; published bytes and pure regions remain owned.
    if jit != nil and index >= 0 and index < int(jit.memoryCycle.count):
      jit.memoryCycle.entries[index].active = false

  proc publishX86MemoryCycle*(jit: X86Jit, candidate: X86MemoryCycleCandidate,
      operands: X86CycleEmission, planIdentity: nil pointer): int =
    ## Manual publication is finite and does not install any source handler on failure.
    result = -1
    if jit == nil or planIdentity == nil or jit.unavailable or
        jit.memoryCycle.count >= 8 or not x86PublicationAvailable(jit): return
    for index in 0..<int(jit.memoryCycle.count):
      if jit.memoryCycle.entries[index].candidate.dirty.header ==
          candidate.dirty.header:
        return
    var image: seq[byte] = @[]
    if not buildX86MemoryCycleImage(candidate, operands, image): return
    if jit.region.status != 2:
      # This private publisher alone leaves one existing fragment and one maximum image available.
      if jit.fragments+1 >= x86TotalFragmentLimit or
          jit.codeBytes > 1024'u64*1024-uint64(image.len)-4126: return
    if jit.arena.handle == nil:
      when defined(pvmX86JitRefuse): discard
      else: jit.arena.handle = createNative()
    if jit.arena.handle == nil:
      jit.unavailable = true
      return
    let published = publishNative(jit.arena.handle, addr image[0], uint32(image.len))
    if published < 0: return
    let index = int(jit.memoryCycle.count)
    jit.memoryCycle.entries[index] = X86MemoryCycleSlot(candidate: candidate,
      planIdentity: planIdentity, code: uint32(published), active: true)
    inc jit.memoryCycle.count
    inc jit.fragments
    jit.codeBytes = uint64(published)+uint64(image.len)
    result = index

  proc callX86MemoryCycle*(jit: X86Jit, index: int, registers: var RegisterFile,
      memory: var X86CycleMemory, dirty: var seq[uint64],
          state: var X86CycleState): uint64 =
    ## A zero high word is only an untouched pre-call refusal; the wrapper validates every native receipt.
    if jit == nil or index < 0 or index >= int(jit.memoryCycle.count) or
        not jit.memoryCycle.entries[index].active or jit.arena.handle == nil:
      return 0
    assert sizeof(X86CycleMemory) == 56 and sizeof(X86CycleState) == 64
    let bitmap: nil pointer = if dirty.len == 0: nil else: addr dirty[0]
    cycleNative(jit.arena.handle, jit.memoryCycle.entries[index].code,
        addr registers[0],
      addr memory, bitmap, addr state)

  proc recordX86MemoryCycle*(jit: X86Jit, prefix, dirty, tail,
      groups: uint64): bool =
    ## Count logical non-noop guest operations only after the complete native ledger is accepted.
    if jit == nil or prefix > high(uint64) div 4 or dirty > high(
        uint64) div 5 or tail > high(uint64) div 3: return false
    let p = prefix*4
    let d = dirty*5
    let t = tail*3
    if p > high(uint64)-d or p+d > high(uint64)-t or
        jit.operations > high(uint64)-(p+d+t) or jit.calls == high(uint64) or
        jit.memoryCycle.calls == high(uint64) or
        jit.memoryCycle.groups > high(uint64)-groups or
        jit.memoryCycle.tails > high(uint64)-tail: return false
    jit.operations += p+d+t
    inc jit.calls
    inc jit.memoryCycle.calls
    jit.memoryCycle.groups += groups
    jit.memoryCycle.tails += tail
    true

  func x86MemoryCycleStatistics*(jit: X86Jit): array[2, uint64] =
    ## Private native invocation and four-block group receipts exclude fallback source attempts.
    if jit == nil: default(array[2, uint64])
    else: [jit.memoryCycle.calls, jit.memoryCycle.groups]

  func x86MemoryCycleTailVisits*(jit: X86Jit): uint64 =
    ## Validated native tail completions exclude checked fallback reads.
    if jit == nil: 0'u64
    else: jit.memoryCycle.tails

  when defined(pvmX86Jit) or defined(pvmX86WideCycleProof):
    const
      wideBranch = 0'u8
      wideRead = 1'u8
      wideChild = 2'u8
      wideOutside = 3'u8
      wideGuard = 4'u8
      wideRare = 5'u8
      wideReadRefusal = 6'u8
      wideBranchGuard = 7'u8
      wideReadGuard = 8'u8
      wideOutsideGuard = 9'u8
      wideGuardGuard = 10'u8
      wideEpilogue = 11'u8
      widePrefix = 12'u8
      widePrefixGuard = 13'u8

    proc wideReturn(code: var X86Block, fixes: var seq[X86CycleFixup],
        kind, header: uint32) =
      ## The wider image has its own epilogue label, separate from the child image.
      put(code, [0x41'u8, 0xc7, 0x47, 0x34])
      cycleWord(code, kind)
      put(code, [0xb8'u8])
      cycleWord(code, header)
      cycleEdge(code, fixes, 0, wideEpilogue)

    proc wideReadOperation(code: var X86Block, fixes: var seq[X86CycleFixup],
        labels: var array[128, int], nextLabel: var int,
        operation: X86WideOperation): bool =
      ## One speculative load reads a complete private extent or returns to canonical replay.
      let opcode = operation.opcode
      if opcode notin {52'u8..58'u8, 124'u8..130'u8} or nextLabel > 122:
        return false
      let index = if opcode <= 58: int(opcode)-52 else: int(opcode)-124
      let width = 1 shl (index div 2)
      let destination = operation.slots.aIndex
      if opcode >= 124:
        put(code, [0x4c'u8, 0x8b, 0x47, byte(int(operation.slots.bIndex)*8)])
        put(code, [0x48'u8, 0xb8])
        cycleQword(code, operation.immediate)
        put(code, [0x49'u8, 0x01, 0xc0]) # ADD R8,RAX before 32-bit address clipping.
      else:
        put(code, [0x49'u8, 0xb8])
        cycleQword(code, operation.immediate)
      put(code, [0x45'u8, 0x89, 0xc0]) # MOV R8D,R8D clips modulo 2^32.
      put(code, [0x49'u8, 0x81, 0xf8])
      cycleWord(code, 65536)
      cycleEdge(code, fixes, 0x82, wideReadRefusal)
      put(code, [0x48'u8, 0xb8])
      cycleQword(code, uint64(high(uint32))-uint64(width))
      put(code, [0x49'u8, 0x39, 0xc0])
      cycleEdge(code, fixes, 0x87, wideReadRefusal)
      let accepted = uint8(nextLabel)
      inc nextLabel
      for region in 0..<3:
        let nextRegion = uint8(nextLabel)
        inc nextLabel
        let pointerOffset = byte(56+region*24)
        let firstOffset = byte(64+region*24)
        let endOffset = byte(72+region*24)
        put(code, [0x49'u8, 0x8b, 0x45, firstOffset]) # MOV RAX,region.first.
        put(code, [0x49'u8, 0x39, 0xc0]) # CMP R8,RAX.
        cycleEdge(code, fixes, 0x82, nextRegion)
        put(code, [0x49'u8, 0x8d, 0x50, byte(width)]) # LEA RDX,[R8+width].
        put(code, [0x49'u8, 0x8b, 0x4d, endOffset]) # MOV RCX,region.ending.
        put(code, [0x48'u8, 0x39, 0xca]) # CMP RDX,RCX.
        cycleEdge(code, fixes, 0x87, wideReadRefusal)
        put(code, [0x49'u8, 0x8b, 0x4d, pointerOffset]) # MOV RCX,region.data.
        put(code, [0x48'u8, 0x85, 0xc9])
        cycleEdge(code, fixes, 0x84, wideReadRefusal)
        put(code, [0x49'u8, 0x29, 0xc0, 0x4c, 0x01, 0xc1]) # In-bounds host pointer.
        case index
        of 0: put(code, [0x48'u8, 0x0f, 0xb6, 0x01])
        of 1: put(code, [0x48'u8, 0x0f, 0xbe, 0x01])
        of 2: put(code, [0x48'u8, 0x0f, 0xb7, 0x01])
        of 3: put(code, [0x48'u8, 0x0f, 0xbf, 0x01])
        of 4: put(code, [0x8b'u8, 0x01])
        of 5: put(code, [0x48'u8, 0x63, 0x01])
        else: put(code, [0x48'u8, 0x8b, 0x01])
        put(code, [0x48'u8, 0x89, 0x47, byte(int(destination)*8)])
        cycleEdge(code, fixes, 0, accepted)
        labels[int(nextRegion)] = code.bytes.len
      cycleEdge(code, fixes, 0, wideReadRefusal)
      labels[int(accepted)] = code.bytes.len
      true

    proc wideScratchCopy(code: var X86Block, publish: bool) =
      ## Copy all 13 registers in source order; the scratch bank is never a guest owner.
      for slot in 0..<13:
        let displacement = byte(slot*8)
        if publish:
          put(code, [0x48'u8, 0x8b, 0x44, 0x24, displacement])
          put(code, [0x49'u8, 0x89, 0x44, 0x24, displacement])
        else:
          put(code, [0x49'u8, 0x8b, 0x44, 0x24, displacement])
          put(code, [0x48'u8, 0x89, 0x44, 0x24, displacement])

    proc buildX86WideCycleImage*(candidate: X86WideCycleCandidate,
        emission: X86WideEmission, imageBase, childCode: uint32,
        image: var seq[byte]): bool =
      ## One bounded linked driver keeps all read effects private until complete success.
      image = @[]
      if childCode >= imageBase or (childCode and 15) != 0 or
          (imageBase and 15) != 0 or imageBase >= 1048576 or
          candidate.readBlock.span > 65 or candidate.readBlock.span < 4 or
          candidate.readOperations == 0 or candidate.readOperations > 64 or
          candidate.readOperations != emission.readCount or
          candidate.cycle.prefix.span == 0 or candidate.cycle.prefix.span > 65 or
          candidate.loopGuard.span != 3 or candidate.loopBranch.span != 1 or
          candidate.cycle.outside.span != 1 or candidate.readLoads < 2 or
          candidate.readLoads > 16: return false
      for operation in emission.guardOperations:
        if not supportedX86Opcode(operation.opcode): return false
      var loadCount = 0'u32
      for index in 0..<int(emission.readCount):
        let opcode = emission.readOperations[index].opcode
        if opcode in {52'u8..58'u8, 124'u8..130'u8}: inc loadCount
        elif not supportedX86Opcode(opcode): return false
      if loadCount != candidate.readLoads: return false
      let headers = [candidate.cycle.prefix.header, candidate.cycle.dirty.header,
        candidate.cycle.tail.header, candidate.cycle.outside.header,
        candidate.loopGuard.header, candidate.loopBranch.header,
        candidate.readBlock.header, candidate.rare.header]
      for header in headers:
        if header >= 262144: return false
      var code = default(X86Block)
      var labels = default(array[128, int])
      for index in 0..<labels.len: labels[index] = -1
      var fixes: seq[X86CycleFixup] = @[]
      var nextLabel = 14
      # Four preserved pointers and 104 scratch bytes leave the stack aligned for the child call.
      put(code, [0x41'u8, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57,
        0x48, 0x83, 0xec, 0x68, 0x49, 0x89, 0xfc, 0x49, 0x89, 0xf5,
        0x49, 0x89, 0xd6, 0x49, 0x89, 0xcf])
      labels[int(wideBranch)] = code.bytes.len
      cycleBudget(code, fixes, candidate.loopBranch.price,
        byte(candidate.loopBranch.span), wideBranchGuard)
      cycleDebit(code, candidate.loopBranch.price, byte(candidate.loopBranch.span))
      put(code, [0x4c'u8, 0x89, 0xe7])
      emitX86Branch(code, 88, emission.loopBranch, emission.loopImmediate,
        candidate.loopBranch.yes, candidate.loopBranch.no)
      cycleComplete(code, 80, 1, candidate.loopBranch.header, false)
      put(code, [0x3d'u8])
      cycleWord(code, candidate.loopGuard.header)
      cycleEdge(code, fixes, 0x84, wideGuard)
      cycleEdge(code, fixes, 0, wideRead)

      labels[int(wideRead)] = code.bytes.len
      cycleBudget(code, fixes, candidate.readBlock.price,
        byte(candidate.readBlock.span), wideReadGuard)
      cycleDebit(code, candidate.readBlock.price, byte(candidate.readBlock.span))
      wideScratchCopy(code, false)
      put(code, [0x48'u8, 0x8d, 0x3c, 0x24]) # LEA RDI,[RSP] selects private registers.
      for index in 0..<int(emission.readCount):
        let operation = emission.readOperations[index]
        if operation.opcode in {52'u8..58'u8, 124'u8..130'u8}:
          if not wideReadOperation(code, fixes, labels, nextLabel, operation): return false
        else:
          emitX86Operation(code, operation.opcode, operation.slots, operation.immediate)
      wideScratchCopy(code, true)
      cycleComplete(code, 88, 1, candidate.readBlock.header, false)
      cycleEdge(code, fixes, 0, widePrefix)

      labels[int(widePrefix)] = code.bytes.len
      cycleBudget(code, fixes, candidate.cycle.prefix.price,
        byte(candidate.cycle.prefix.span), widePrefixGuard)
      cycleDebit(code, candidate.cycle.prefix.price,
        byte(candidate.cycle.prefix.span))
      put(code, [0x4c'u8, 0x89, 0xe7])
      emitX86Operation(code, 51, emission.prefix.prefixLoad,
        candidate.cycle.initialShift)
      emitX86Operation(code, 200, emission.prefix.prefixBound, 0)
      emitX86Operation(code, 149, emission.prefix.prefixStep, 1)
      cycleComplete(code, 16, 1, candidate.cycle.prefix.header, false)
      cycleEdge(code, fixes, 0, wideChild)

      labels[int(wideChild)] = code.bytes.len
      put(code, [0x49'u8, 0xff, 0x47, 0x60]) # One immutable child image call.
      put(code, [0x4c'u8, 0x89, 0xe7, 0x4c, 0x89, 0xee,
        0x4c, 0x89, 0xf2, 0x4c, 0x89, 0xf9, 0xe8])
      let callOrigin = uint64(imageBase)+uint64(code.bytes.len)+4
      if callOrigin > 1048576: return false
      let relative = int64(childCode)-int64(callOrigin)
      let encoded = if relative >= 0: uint32(relative)
        else: 0'u32-uint32(-relative)
      cycleWord(code, encoded)
      put(code, [0x3d'u8])
      cycleWord(code, candidate.cycle.outside.header)
      cycleEdge(code, fixes, 0x84, wideOutside)
      cycleEdge(code, fixes, 0, wideEpilogue) # Child guard preserves its own receipt.

      labels[int(wideOutside)] = code.bytes.len
      cycleBudget(code, fixes, candidate.cycle.outside.price,
        byte(candidate.cycle.outside.span), wideOutsideGuard)
      cycleDebit(code, candidate.cycle.outside.price, byte(candidate.cycle.outside.span))
      cycleComplete(code, 64, 1, candidate.cycle.outside.header, false)
      cycleEdge(code, fixes, 0, wideGuard)

      labels[int(wideGuard)] = code.bytes.len
      cycleBudget(code, fixes, candidate.loopGuard.price,
        byte(candidate.loopGuard.span), wideGuardGuard)
      cycleDebit(code, candidate.loopGuard.price, byte(candidate.loopGuard.span))
      put(code, [0x4c'u8, 0x89, 0xe7])
      for operation in emission.guardOperations:
        emitX86Operation(code, operation.opcode, operation.slots, operation.immediate)
      emitX86Branch(code, 81, emission.guardBranch, emission.guardImmediate,
        candidate.loopGuard.yes, candidate.loopGuard.no)
      cycleComplete(code, 72, 1, candidate.loopGuard.header, false)
      put(code, [0x3d'u8])
      cycleWord(code, candidate.loopBranch.header)
      cycleEdge(code, fixes, 0x84, wideBranch)
      cycleEdge(code, fixes, 0, wideRare)

      labels[int(wideRare)] = code.bytes.len
      wideReturn(code, fixes, 2, candidate.rare.header)
      labels[int(wideReadRefusal)] = code.bytes.len
      wideReturn(code, fixes, 3, candidate.readBlock.header+1)
      labels[int(wideBranchGuard)] = code.bytes.len
      wideReturn(code, fixes, 1, candidate.loopBranch.header)
      labels[int(wideReadGuard)] = code.bytes.len
      wideReturn(code, fixes, 1, candidate.readBlock.header)
      labels[int(wideOutsideGuard)] = code.bytes.len
      wideReturn(code, fixes, 1, candidate.cycle.outside.header)
      labels[int(wideGuardGuard)] = code.bytes.len
      wideReturn(code, fixes, 1, candidate.loopGuard.header)
      labels[int(widePrefixGuard)] = code.bytes.len
      wideReturn(code, fixes, 1, candidate.cycle.prefix.header)
      labels[int(wideEpilogue)] = code.bytes.len
      put(code, [0x48'u8, 0x83, 0xc4, 0x68, 0x41, 0x5f, 0x41, 0x5e,
        0x41, 0x5d, 0x41, 0x5c, 0xc3])
      if code.bytes.len == 0 or code.bytes.len > 4096: return false
      for fix in fixes:
        if int(fix.target) >= labels.len or labels[int(fix.target)] < 0:
          return false
        let displacement = int64(labels[int(fix.target)])-int64(fix.at+4)
        let value = if displacement >= 0: uint32(displacement)
          else: 0'u32-uint32(-displacement)
        for shift in 0..<4:
          code.bytes[fix.at+shift] = byte((value shr (shift*8)) and 255)
      image = move(code.bytes)
      true

    proc wideNative(handle: nil pointer, offset: uint32, registers: pointer,
        memory, dirty, state: nil pointer): uint64
        {.cdecl, importc: "pvm_x86_arena_wide", header: "x86_memory.h".}
      ## A zero high word proves the typed C boundary refused before invoking native bytes.

    func x86WideActive*(jit: X86Jit): bool =
      ## Only a successfully published, source-bound image may be called.
      jit != nil and jit.wideCycle.status == 2

    func x86WideCanPublish*(jit: X86Jit): bool =
      ## Local source refusals keep this owner eligible; consumed storage does not.
      jit != nil and jit.wideCycle.status == 0

    when defined(pvmX86WideParentRefusalWitness):
      proc x86WideRefuseParentOnceWitness*(jit: X86Jit) =
        ## Isolate the child-published/parent-refused transaction in one native unit profile.
        assert jit != nil
        jit.wideCycle.refuseParentOnce = true

    func x86WideCandidate*(jit: X86Jit): X86WideCycleCandidate =
      ## Copy the source proof without exposing the owner's callable code offset.
      assert x86WideActive(jit)
      jit.wideCycle.candidate

    func x86WideBound*(jit: X86Jit, planIdentity: nil pointer): bool =
      ## Restored frames may move; their immutable plan must remain the publication owner.
      x86WideActive(jit) and planIdentity != nil and
        jit.wideCycle.planIdentity == planIdentity

    proc x86WidePublishedSourceImage*(jit: X86Jit, emission: X86WideEmission,
        image: var seq[byte]): bool =
      ## Rebuild the published source bytes from its retained code offsets, without
      ## reading the executable arena or changing the callable owner.
      image = @[]
      if not x86WideActive(jit) or jit.wideCycle.code >= jit.codeBytes or
          jit.wideCycle.childCode >= jit.wideCycle.code: return false
      if not buildX86WideCycleImage(jit.wideCycle.candidate, emission,
          jit.wideCycle.code, jit.wideCycle.childCode, image): return false
      uint64(jit.wideCycle.code)+uint64(image.len) == jit.codeBytes

    proc retireX86Wide*(jit: X86Jit) =
      ## Retirement leaves the published child and all original handlers available.
      if jit != nil and jit.wideCycle.status == 2: jit.wideCycle.status = 3

    proc publishX86WideCycle*(jit: X86Jit, candidate: X86WideCycleCandidate,
        emission: X86WideEmission, childSlot: int, planIdentity: nil pointer): bool =
      ## One bounded driver links an existing immutable child without copying or replacing it.
      if jit == nil or jit.wideCycle.status != 0 or planIdentity == nil or
          jit.unavailable or not x86PublicationAvailable(jit) or
          childSlot < 0 or childSlot >= int(jit.memoryCycle.count): return false
      let child = jit.memoryCycle.entries[childSlot]
      if not child.active or child.planIdentity != planIdentity or
          child.candidate != candidate.cycle or child.code >= jit.codeBytes or
          jit.arena.handle == nil or jit.codeBytes > 1048576'u64-4112'u64:
        return false
      when defined(pvmX86WideParentRefusalWitness):
        if jit.wideCycle.refuseParentOnce:
          jit.wideCycle.refuseParentOnce = false
          return false
      let planned = uint32((jit.codeBytes+15'u64) and not 15'u64)
      var image: seq[byte] = @[]
      if not buildX86WideCycleImage(candidate, emission, planned, child.code, image):
        return false
      if jit.region.status != 2 and
          (jit.fragments+1 >= x86TotalFragmentLimit or
            jit.codeBytes > 1048576'u64-uint64(image.len)-4126'u64):
        jit.wideCycle.status = 1
        return false
      jit.wideCycle.status = 1
      let published = publishNative(jit.arena.handle, addr image[0], uint32(image.len))
      if published < 0: return false
      inc jit.fragments
      jit.codeBytes = uint64(published)+uint64(image.len)
      if uint32(published) != planned: return false # Account for an unexpected occupied slot.
      jit.wideCycle.candidate = candidate
      jit.wideCycle.planIdentity = planIdentity
      jit.wideCycle.code = uint32(published)
      jit.wideCycle.childCode = child.code
      jit.wideCycle.status = 2
      true

    proc callX86WideCycle*(jit: X86Jit, registers: var RegisterFile,
        memory: var X86WideMemory, dirty: var seq[uint64],
        state: var X86WideState): uint64 =
      ## The four invocation borrows outlive exactly one guarded native call.
      if not x86WideActive(jit) or jit.arena.handle == nil: return 0
      assert sizeof(X86WideMemory) == 128 and sizeof(X86WideState) == 104
      let bitmap: nil pointer = if dirty.len == 0: nil else: addr dirty[0]
      wideNative(jit.arena.handle, jit.wideCycle.code, addr registers[0],
        addr memory, bitmap, addr state)

    proc recordX86WideCycle*(jit: X86Jit, candidate: X86WideCycleCandidate,
        state: X86WideState): bool =
      ## Publish only validated logical child/outer work without counter overflow.
      if not x86WideActive(jit) or jit.calls == high(uint64) or
          jit.wideCycle.calls == high(uint64) or
          jit.memoryCycle.calls > high(uint64)-state.childCalls or
          jit.memoryCycle.groups > high(uint64)-state.cycle.wordGroups or
          jit.memoryCycle.tails > high(uint64)-state.cycle.visits[2] or
          (state.cycle.exitKind == 3 and jit.wideCycle.readRefusals == high(uint64)):
        return false
      let counts = [state.cycle.visits[0], state.cycle.visits[1],
        state.cycle.visits[2], state.outerVisits[0], state.outerVisits[1],
        state.outerVisits[2], state.outerVisits[3]]
      let nodes = [4'u64, 5, 3, 1, 3, 1,
        uint64(candidate.readOperations)+1'u64] # Include the completed cached jump.
      var operations = 0'u64
      for index in 0..<counts.len:
        if nodes[index] != 0 and counts[index] > high(uint64) div nodes[index]:
          return false
        let part = counts[index]*nodes[index]
        if operations > high(uint64)-part: return false
        operations += part
      if jit.operations > high(uint64)-operations: return false
      jit.operations += operations
      inc jit.calls
      inc jit.wideCycle.calls
      jit.memoryCycle.calls += state.childCalls
      jit.memoryCycle.groups += state.cycle.wordGroups
      jit.memoryCycle.tails += state.cycle.visits[2]
      if state.cycle.exitKind == 3: inc jit.wideCycle.readRefusals
      true

    func x86WideStatistics*(jit: X86Jit): array[2, uint64] =
      ## Distinguish wide entries from later-read canonical replays.
      if jit == nil: default(array[2, uint64])
      else: [jit.wideCycle.calls, jit.wideCycle.readRefusals]
