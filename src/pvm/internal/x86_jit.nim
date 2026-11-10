# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent Linux x86-64 arithmetic lowering; source charging and every observable boundary stay in the interpreter.
## The canonical SysV leaf borrows one register array in RDI and touches only caller-saved registers.
## A separate default-off proof may preserve a bounded resident bank; neither path retains input pointers.

import std/assertions
import ../[program, machine]
import ./native_register_ring
import ./jit_rules
import ./[native_control, native_ir]
import ./native_read_body
when defined(pvmX86Jit) and NativeReadCycleEnabled:
  import ./native_read_cycle

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
      Other, Ordinary, CheckedWord
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
    spans, operations: array[2, uint32]
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

proc takeX86Instructions*(fragment: var X86Block): seq[byte] =
  ## Transfer only machine bytes to the shared worker; no legacy admission/publication rule is invoked.
  move(fragment.bytes)

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

type X86CanonicalAccess = object
  ## Empty cold lowering policy keeps the original RDI register-array instruction forms.

proc readAccess(fragment: var X86Block, access: X86CanonicalAccess,
    slot: range[0..12], right: bool) =
  ## Canonical operands preserve the exact original memory load bytes.
  readSlot(fragment, slot, right)

proc writeAccess(fragment: var X86Block, access: X86CanonicalAccess, slot: range[0..12]) =
  ## RAX is committed after every operation exactly as before accessor parameterization.
  put(fragment, [0x48'u8, 0x89, 0x47, byte(int(slot)*8)])

when (defined(pvmX86Jit) and NativeCheckedReadEnabled) or defined(pvmX86ResidentProof):
  include ./x86_resident_access

template emitX86OperationAccess(fragment: var X86Block, access: untyped, opcode: byte,
    slots: RegisterSlots, value: uint64) =
  ## Scratch RAX/RCX/RDX/R8 obey SysV caller-save rules; all aliases consume their old inputs first.
  assert supportedX86Opcode(opcode)
  if opcode in [20'u8, 51]:
    immediate(fragment, 0xb8, value)
  elif opcode == 100 or opcode in {107'u8..110}:
    readAccess(fragment, access, slots.aIndex, false)
    case opcode
    of 107: put(fragment, [0x48'u8, 0x0f, 0xbe, 0xc0]) # MOVSX RAX,AL.
    of 108: put(fragment, [0x48'u8, 0x0f, 0xbf, 0xc0]) # MOVSX RAX,AX.
    of 109: put(fragment, [0x0f'u8, 0xb7, 0xc0]) # MOVZX EAX,AX also clears the high word.
    of 110: put(fragment, [0x48'u8, 0x0f, 0xc8]) # BSWAP RAX.
    else: discard # The loaded A value is already the complete move result.
  else:
    if opcode < 190:
      readAccess(fragment, access, slots.bIndex, false)
      immediate(fragment, 0xb9, value)
    else:
      readAccess(fragment, access, slots.aIndex, false)
      readAccess(fragment, access, slots.bIndex, true)
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
  writeAccess(fragment, access, slots.destinationIndex)

template emitX86BranchAccess(fragment: var X86Block, access: untyped, opcode: byte,
    slots: RegisterSlots,
    value: uint64, yes, no: uint32) =
  ## Positive checked stream destinations become immediate scalar results; MOV/CMOV preserve the full-width comparison.
  assert opcode in {81'u8..90, 170..175}
  assert yes < 2147483646'u32 and no < 2147483646'u32
  readAccess(fragment, access, slots.aIndex, false)
  if opcode <= 90: immediate(fragment, 0xb9, value)
  else: readAccess(fragment, access, slots.bIndex, true)
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

proc emitX86Operation*(fragment: var X86Block, opcode: byte, slots: RegisterSlots,
    value: uint64) =
  ## Existing consumers keep canonical array reads/writes and exactly the same machine bytes.
  emitX86OperationAccess(fragment, X86CanonicalAccess(), opcode, slots, value)

proc emitX86Branch*(fragment: var X86Block, opcode: byte, slots: RegisterSlots,
    value: uint64, yes, no: uint32) =
  ## Canonical branch lowering shares its only opcode switch with the private resident backend.
  emitX86BranchAccess(fragment, X86CanonicalAccess(), opcode, slots, value, yes, no)

when defined(pvmX86ResidentProof):
  proc emitX86ResidentOperation*(fragment: var X86Block, access: X86ResidentAccess,
      opcode: byte, slots: RegisterSlots, value: uint64) =
    ## Hardware-only lowering grants no source, price, memory or publication authority.
    emitX86OperationAccess(fragment, access, opcode, slots, value)

  proc emitX86ResidentBranch*(fragment: var X86Block, access: X86ResidentAccess,
      opcode: byte, slots: RegisterSlots, value: uint64, yes, no: uint32) =
    ## Comparisons read the same current mapped operands used by scalar operations.
    emitX86BranchAccess(fragment, access, opcode, slots, value, yes, no)

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

type X86LoopFixup = object ## One little-endian rel32 displacement in the shared action stream.
  at: int
  target: LoopLabel

proc x86LoopEdge(fragment: var X86Block, fixes: var seq[X86LoopFixup],
    target: LoopLabel, opcode: openArray[byte]) =
  ## Emit the selected JMP/Jcc opcode followed by its four-byte displacement placeholder.
  put(fragment, opcode)
  fixes.add(X86LoopFixup(at: fragment.bytes.len, target: target))
  regionWord(fragment, 0) # rel32=0, little-endian from immediately after the displacement.

proc encodeX86Loop*(span: NativeSpan, control: LoopControl): seq[byte] =
  ## Lower the shared actions with canonical scalar loads/stores and SysV caller-saved lanes.
  # ARM/x86 gap: encodeArmLoop retains guest lanes across loop iterations; this emitter
  # accesses their array for each operation. Revisit loop residency while preserving the
  # shared LoopControl guard, debit, continuation and final register-publication ordering.
  let loop = span.loopInfo
  let immediateWord = uint32(loop.rightImmediate and 0xffffffff'u64)
  if loop.rightKind == NativeLoopRightKind.Immediate and
      cast[uint64](int64(cast[int32](immediateWord))) != loop.rightImmediate:
    # CMP RAX,imm32 can represent exactly the sign-extended checked operand.
    return @[]
  var fragment = default(X86Block)
  var labels = default(array[LoopLabel, int])
  var fixes: seq[X86LoopFixup] = @[]
  for action in control:
    # RDI is the guest array. RSI is context, R9/R10 are gas/quota, and R11 counts visits.
    case action.kind
    of LoadContext:
      put(fragment, [0x4c'u8, 0x8b, 0x0e]) # MOV R9,[RSI]: gas.
      put(fragment, [0x4c'u8, 0x8b, 0x56, 8]) # MOV R10,[RSI+8]: remaining attempts.
      put(fragment, [0x45'u8, 0x31, 0xdb]) # XOR R11D,R11D: zero-extend visits.
    of LoadGuest, StoreGuest:
      # Canonical scalar instructions already load and store their own guest operands.
      discard
    of Label:
      labels[action.target] = fragment.bytes.len
    of ExecuteBody:
      for index in 0..<span.len:
        # Canonical scalar emission preserves RSI/RDI and the three context lanes.
        let op = span.operation(index)
        emitX86Operation(fragment, op.opcode, op.slots, op.immediate)
    of CountVisit:
      put(fragment, [0x49'u8, 0xff, 0xc3]) # INC R11: one completed original body and branch.
    of BranchGuestAboveEqual:
      readSlot(fragment, loop.slots.aIndex, false) # MOV RAX,[RDI+left*8].
      if loop.rightKind == NativeLoopRightKind.Immediate:
        put(fragment, [0x48'u8, 0x3d]) # CMP RAX,imm32: REX.W sign-extends the immediate to 64 bits.
        regionWord(fragment, immediateWord) # Little-endian imm32, verified above against the certificate.
      else:
        readSlot(fragment, loop.slots.bIndex, true) # MOV RCX,[RDI+right*8].
        put(fragment, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX: compare original unsigned operands.
      x86LoopEdge(fragment, fixes, action.target, [0x0f'u8, 0x83]) # JAE rel32.
    of BranchLaneBelow, DebitLane:
      let lane = if action.lane == Gas: 1'u8 else: 2'u8
      let compare = action.kind == BranchLaneBelow
      if action.value <= 0x7fffffff'u64:
        # CMP/SUB R9 or R10,imm32; ModRM /7 or /5, REX.B extends the lane.
        let field = if compare: 0xf8'u8 else: 0xe8'u8
        put(fragment, [0x49'u8, 0x81, field or lane])
        regionWord(fragment, uint32(action.value)) # Sign-extended immediate is nonnegative here.
      else:
        immediate(fragment, 0xb8, action.value) # MOV RAX,imm64: full unsigned amount.
        # CMP/SUB R9 or R10,RAX; REX.B extends the destination lane.
        let opcode = if compare: 0x39'u8 else: 0x29'u8
        put(fragment, [0x49'u8, opcode, 0xc0'u8 or lane])
      if compare:
        x86LoopEdge(fragment, fixes, action.target, [0x0f'u8, 0x82]) # JB rel32.
    of Jump:
      x86LoopEdge(fragment, fixes, action.target, [0xe9'u8]) # JMP rel32.
    of SelectReturn:
      put(fragment, [0xb8'u8]) # MOV EAX,imm32: return the selected stream coordinate.
      regionWord(fragment, uint32(action.value)) # Immediate holds the bounded uint32 coordinate.
    of StoreContext:
      put(fragment, [0x4c'u8, 0x89, 0x0e]) # MOV [RSI],R9: gas.
      put(fragment, [0x4c'u8, 0x89, 0x56, 8]) # MOV [RSI+8],R10: quota.
      put(fragment, [0x4c'u8, 0x89, 0x5e, 16]) # MOV [RSI+16],R11: completed visits.
    of Return:
      put(fragment, [0xc3'u8]) # RET: pop caller RIP with the SysV stack otherwise untouched.
  if fragment.bytes.len > NativeImageByteLimit: return @[]
  for fix in fixes:
    # The image ceiling proves a signed rel32, measured from after its four-byte field.
    let displacement = cast[uint32](int32(labels[fix.target]-(fix.at+4)))
    for part in 0..<4:
      fragment.bytes[fix.at+part] = byte((displacement shr (part*8)) and 255)
  takeX86Instructions(fragment)

proc x86RegionBytes(blocks: openArray[X86RegionBlock], rotating: bool): seq[byte] =
  ## Emit full guards and canonical guest accesses using SysV caller-saved registers.
  let count = blocks.len
  assert count in 1..3
  var code = default(X86Block)
  # RDI is the guest array, RSI the fresh context, and bodies only touch RAX/RCX/RDX/R8.
  put(code, [0x4c'u8, 0x8b, 0x0e, 0x4c, 0x8b, 0x56, 8])
  var labels = default(array[3, int])
  var fixes: seq[X86RegionFixup] = @[]
  if rotating:
    # Entry zero falls through after the wrapper validates the complete rotation index.
    for index in 1..2:
      put(code, [0x48'u8, 0x83, 0x7e, 40, byte(index)]) # CMP QWORD [RSI+40],index.
      regionEdge(code, fixes, blocks[index].header, 0x84, false) # JE guarded header.
  for index in 0..<count:
    let item = blocks[index]
    if item.header >= 262144 or item.span < 2 or item.span > 65 or
        item.operations != item.span or item.body.bytes.len < 16: return @[]
    let terminal = item.body.bytes.len
    # Only the existing emitter's MOV/MOV/CMOV scalar-selection tail can be replaced by native edges.
    if item.body.bytes[terminal-13] != 0xb8 or item.body.bytes[terminal-8] != 0xba or
        item.body.bytes[terminal-3] != 0x0f or item.body.bytes[terminal-1] != 0xc2: return @[]
    let condition = item.body.bytes[terminal-2]
    if condition notin {0x42'u8..0x47, 0x4c..0x4f}: return @[]
    labels[index] = code.bytes.len
    put(code, [0x49'u8, 0x81, 0xfa]) # CMP R10,wholeSourceSpan; partial blocks return before debit.
    regionWord(code, item.span)
    regionEdge(code, fixes, item.header, 0x82, true)
    immediate(code, 0xb8, item.price)
    put(code, [0x49'u8, 0x39, 0xc1]) # CMP R9,RAX is an unsigned full64 gas guard.
    regionEdge(code, fixes, item.header, 0x82, true)
    put(code, [0x49'u8, 0x29, 0xc1, 0x49, 0x81, 0xea])
    regionWord(code, item.span)
    # Count each complete visit. The legacy ABI also publishes its last completed header.
    put(code, [0x48'u8, 0xff, 0x46, byte(16+index*8)])
    if not rotating:
      put(code, [0x48'u8, 0xc7, 0x46, 32])
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
  if code.bytes.len >= 4096: return @[]
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
  takeX86Instructions(code)

proc encodeX86RegisterRing*(ring: NativeRegisterRing): seq[byte] =
  ## Reuse the canonical region builder with three distinct visit lanes.
  var blocks = default(array[3, X86RegionBlock])
  for index in 0..2:
    let item = ring.blocks[index]
    var body = default(X86Block)
    for operation in 0..<int(item.span)-1:
      let op = item.body[operation]
      emitX86Operation(body, op.opcode, op.slots, op.immediate)
    let branch = item.branch
    emitX86Branch(body, branch.opcode, branch.slots, branch.immediate, item.yes, item.no)
    blocks[index] = X86RegionBlock(header: item.header, span: item.span,
      operations: item.span, yes: item.yes, no: item.no, price: item.price, body: move(body))
  x86RegionBytes(blocks, true)

proc publishX86Region*(jit: X86Jit, blocks: array[2, X86RegionBlock], count: range[1..2]): bool =
  ## Preserve the legacy publisher and its two-block receipt.
  assert jit.region.status == 0
  var code = x86RegionBytes(blocks.toOpenArray(0, int(count)-1), false)
  if code.len == 0: return false
  if not x86PublicationAvailable(jit, region = true):
    # Exhausted owner-wide publication capacity is permanent.
    jit.region.status = 1
    return false
  # Only proven owner-wide capacity/storage failure is sticky; local negatives exhaust existing per-header probes.
  jit.region.status = 1
  if jit.arena.handle == nil: return false
  let published = publishNative(jit.arena.handle, addr code[0], uint32(code.len))
  if published < 0: return false
  jit.region.code = uint32(published)
  for index in 0..<count:
    jit.region.spans[index] = blocks[index].span
    jit.region.operations[index] = blocks[index].operations
  jit.region.count = uint32(count)
  jit.region.status = 2
  inc jit.fragments
  jit.codeBytes = uint64(published)+uint64(code.len)
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

  when defined(pvmX86Jit) and NativeCheckedReadEnabled:
    proc readBodyReturn(code: var X86Block, status: uint32) =
      ## Both exits restore the same SysV stack frame and define the complete scalar return.
      put(code, [0xb8'u8]) # MOV EAX,status returns success or refusal and clears the upper word.
      cycleWord(code, status)
      put(code, [0x48'u8, 0x83, 0xc4, 0x68]) # ADD RSP,104 releases the private register stage.
      put(code, [0xc3'u8]) # RET consumes the original caller return RIP.

    func readBodyDirty(body: NativeReadBody, count: int): uint32 =
      ## Select only the destinations the existing checked-read certificate can write.
      result = 0
      for index in 0..<count:
        let op = body.operation(index)
        let slot = if nativeReadOpcode(nativeReadEncodingOpcode(op.opcode)): op.slots.aIndex
          else: op.slots.destinationIndex
        result = result or (1'u32 shl int(slot))

    proc readBodyBase(code: var X86Block, access: X86CanonicalAccess, slot: range[0..12]) =
      put(code, [0x8b'u8, 0x57, byte(slot*8)]) # MOV EDX,[RDI+slot*8].

    type X86CheckedReadAccess = object
      bank: X86ResidentAccess
      liveIns, written: uint32

    proc readBodyLiveIn(access: var X86CheckedReadAccess, slot: range[0..12]) =
      let bit = 1'u32 shl int(slot)
      if access.bank.registers[slot] != 0 and (access.written and bit) == 0:
        access.liveIns = access.liveIns or bit

    proc readAccess(code: var X86Block, access: var X86CheckedReadAccess,
        slot: range[0..12], right: bool) =
      readBodyLiveIn(access, slot)
      readAccess(code, access.bank, slot, right)

    proc writeAccess(code: var X86Block, access: var X86CheckedReadAccess, slot: range[0..12]) =
      assert access.bank.registers[slot] != 0 # Unmapped lanes are read-only throughout this leaf.
      writeAccess(code, access.bank, slot)
      access.written = access.written or (1'u32 shl int(slot))

    proc readBodyBase(code: var X86Block, access: X86ResidentAccess, slot: range[0..12]) =
      ## Address arithmetic starts with the low word of the current logical lane.
      let encoded = access.registers[slot]
      if encoded == 0:
        readBodyBase(code, X86CanonicalAccess(), slot)
      else:
        let hardware = encoded-1
        if hardware >= 8: put(code, [0x41'u8]) # REX.B selects R12–R15D when required.
        put(code, [0x8b'u8, byte(0xd0 or (hardware and 7))]) # MOV EDX,resident32.

    proc readBodyBase(code: var X86Block, access: var X86CheckedReadAccess, slot: range[0..12]) =
      ## Track read-before-write only when building a transactional Read stage.
      readBodyLiveIn(access, slot)
      readBodyBase(code, access.bank, slot)

    proc emitCheckedExtent(code: var X86Block, fixes: var seq[X86CycleFixup],
        base, width, miss, accepted: byte) =
      ## Use the complete width before exposing a pointer. RDX is the zero-extended address.
      put(code, [0x49'u8, 0x8b, 0x4a, base+8]) # MOV RCX,[R10+extent.length].
      put(code, [0x48'u8, 0x83, 0xe9, width]) # SUB RCX,width gives the final legal offset.
      cycleEdge(code, fixes, 0x82, miss) # JB rel32 on length underflow.
      put(code, [0x48'u8, 0x89, 0xd0]) # MOV RAX,RDX.
      put(code, [0x49'u8, 0x2b, 0x42, base]) # SUB RAX,[R10+extent.first].
      put(code, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX also rejects a wrapped below-base offset.
      cycleEdge(code, fixes, 0x87, miss) # JA rel32 when the complete access cannot fit.
      put(code, [0x49'u8, 0x8b, 0x4a, base+16]) # MOV RCX,[R10+extent.data].
      cycleEdge(code, fixes, 0, accepted) # JMP rel32 with the proved pointer and offset.

    template emitCheckedReadOperations(code: var X86Block, fixes: var seq[X86CycleFixup],
        labels: untyped, body: NativeReadBody, access: untyped,
        count: int, refusal: byte, nextLabel: var byte,
        window: NativeReadWindow = default(NativeReadWindow)) =
      ## Preserve one guard and load emitter for standalone and transactional cycle reads.
      for index in 0..<count:
        let op = body.operation(index)
        let encoding = nativeReadEncodingOpcode(op.opcode)
        if not nativeReadOpcode(encoding):
          emitX86OperationAccess(code, access, op.opcode, op.slots, op.immediate)
        elif (window.operations and (1'u32 shl index)) != 0:
          # RSI holds this entry's first-descriptor window. Load bytes at the original position.
          let offset = uint32(op.immediate and 0xffffffff'u64)-window.first
          assert op.opcode == 130 and offset <= 32
          put(code, [0x48'u8, 0x8b, 0x46, byte(offset)]) # MOV RAX,[RSI+offset].
          writeAccess(code, access, op.slots.aIndex)
        else:
          let opcode = int(encoding)
          assert opcode >= 124 and opcode <= 130 # Prove the local width-table conversion.
          let width = byte(indirectMemoryAccess(range[120..130](opcode)).width)
          if encoding != op.opcode:
            # MOV EDX,imm32 zero-extends the absolute address without a guest live-in.
            put(code, [0xba'u8])
          else:
            # Read the old base even when this load replaces that lane.
            readBodyBase(code, access, op.slots.bIndex)
            put(code, [0x81'u8, 0xc2]) # ADD EDX,imm32 wraps modulo 2^32.
          cycleWord(code, uint32(op.immediate and 0xffffffff'u64))
          # One accept label and three skip labels per load fit the fact-bounded table.
          let accepted = uint8(nextLabel)
          inc nextLabel
          for region in 0..<3:
            let nextRegion = nextLabel
            inc nextLabel
            emitCheckedExtent(code, fixes, byte(region*24), width, nextRegion, accepted)
            labels[int(nextRegion)] = code.bytes.len
          cycleEdge(code, fixes, 0, refusal) # JMP rel32 when all three extents miss.
          labels[int(accepted)] = code.bytes.len
          case encoding
          of 124: put(code, [0x0f'u8, 0xb6, 0x04, 0x01]) # MOVZX EAX,byte [RCX+RAX].
          of 125: put(code, [0x48'u8, 0x0f, 0xbe, 0x04, 0x01]) # MOVSX RAX,byte [RCX+RAX].
          of 126: put(code, [0x0f'u8, 0xb7, 0x04, 0x01]) # MOVZX EAX,word [RCX+RAX] clears upper32.
          of 127: put(code, [0x48'u8, 0x0f, 0xbf, 0x04, 0x01]) # MOVSX RAX,word [RCX+RAX].
          of 128: put(code, [0x8b'u8, 0x04, 0x01]) # MOV EAX,dword [RCX+RAX] clears upper32.
          of 129: put(code, [0x48'u8, 0x63, 0x04, 0x01]) # MOVSXD RAX,dword [RCX+RAX].
          of 130: put(code, [0x48'u8, 0x8b, 0x04, 0x01]) # MOV RAX,qword [RCX+RAX].
          else: assert false # The common certificate admits only these seven load encodings.
          writeAccess(code, access, op.slots.aIndex)

    proc sealCheckedRead(code: var X86Block, fixes: seq[X86CycleFixup],
        labels: array[1+4*int(NativeReadFactLimit), int]): seq[byte] =
      if code.bytes.len > NativeImageByteLimit: return @[]
      for fix in fixes:
        # All targets are forward and fit rel32 under the image byte ceiling.
        let target = labels[int(fix.target)]
        assert target >= fix.at+4 and target < code.bytes.len
        let delta = uint32(target-(fix.at+4))
        for shift in 0..<4:
          code.bytes[fix.at+shift] = byte((delta shr (shift*8)) and 255)
      takeX86Instructions(code)

    proc checkedReadStackInstructions(body: NativeReadBody, dirty: uint32): seq[byte] =
      ## Stage the certified body on the stack, then commit only its written slots.
      assert body.complete and sizeof(RegisterFile) == 104
      var code = default(X86Block)
      var fixes: seq[X86CycleFixup] = @[]
      var labels = default(array[1+4*int(NativeReadFactLimit), int])
      let access = X86CanonicalAccess()

      # No calls or callee-saved registers. R10/R11 retain the two SysV borrows.
      put(code, [0x48'u8, 0x83, 0xec, 0x68]) # SUB RSP,104 reserves the 13-slot stage.
      put(code, [0x49'u8, 0x89, 0xf2]) # MOV R10,RSI saves the extent table.
      put(code, [0x49'u8, 0x89, 0xfb]) # MOV R11,RDI saves the original register file.
      put(code, [0x48'u8, 0x89, 0xfe]) # MOV RSI,RDI sets the copy source.
      put(code, [0x48'u8, 0x89, 0xe7]) # MOV RDI,RSP sets the copy destination.
      put(code, [0xb9'u8]) # MOV ECX,13 selects the complete register file.
      cycleWord(code, 13)
      put(code, [0xf3'u8, 0x48, 0xa5]) # REP MOVSQ copies forward with SysV's clear direction flag.
      put(code, [0x48'u8, 0x89, 0xe7]) # MOV RDI,RSP points canonical emission at the stage.

      var nextLabel = 1'u8
      emitCheckedReadOperations(code, fixes, labels, body, access, body.len, 0, nextLabel)

      for slot in 0..12:
        # Only the success epilogue can publish guest registers after all guards pass.
        if (dirty and (1'u32 shl slot)) != 0:
          readSlot(code, slot, false) # MOV RAX,[RDI+slot*8] reads the final staged value.
          put(code, [0x49'u8, 0x89, 0x43, byte(slot*8)]) # MOV [R11+slot*8],RAX commits one slot.
      readBodyReturn(code, NativeReadSuccess)

      # Every guard miss jumps here before caller-visible stores and discards all staged work.
      labels[0] = code.bytes.len
      readBodyReturn(code, NativeReadRefusal)
      sealCheckedRead(code, fixes, labels)

    proc saveCheckedReadRegister(code: var X86Block, hardware: uint8) =
      ## Save one selected SysV register before changing it.
      if hardware >= 8: put(code, [0x41'u8]) # REX.B extends the PUSH register.
      put(code, [byte(0x50 or (hardware and 7))]) # PUSH resident64.

    proc loadCheckedReadRegister(code: var X86Block, bank: X86ResidentAccess,
        slot: range[0..12]) =
      ## Load one mapped lane from the current canonical file or Read checkpoint.
      let encoded = bank.registers[slot]
      assert encoded != 0
      let hardware = encoded-1
      put(code, [byte(if hardware >= 8: 0x4c else: 0x48), 0x8b,
        byte(0x47 or ((hardware and 7) shl 3)), byte(slot*8)]) # MOV resident64,[RDI+slot*8].

    proc loadCheckedReadLiveIn(code: var X86Block, access: X86CheckedReadAccess,
        slot: range[0..12]) =
      ## Initialize a mapped read-before-write lane from the current canonical file.
      if (access.liveIns and (1'u32 shl int(slot))) != 0:
        loadCheckedReadRegister(code, access.bank, slot)

    proc restoreCheckedReadRegisters(code: var X86Block, bank: X86ResidentAccess) =
      ## Restore every selected SysV register in reverse save order.
      for index in 0..12:
        let encoded = bank.registers[12-index]
        if encoded != 0:
          let hardware = encoded-1
          if hardware >= 8: put(code, [0x41'u8]) # REX.B extends the POP register.
          put(code, [byte(0x58 or (hardware and 7))]) # POP resident64.

    proc commitCheckedReadRegisters(code: var X86Block, bank: X86ResidentAccess,
        mask = 0x1fff'u32) =
      ## Publish the selected mapped lanes after all guards, or save a pre-Read checkpoint.
      for slot in 0..12:
        let encoded = bank.registers[slot]
        if encoded != 0 and (mask and (1'u32 shl slot)) != 0:
          let hardware = encoded-1
          put(code, [byte(if hardware >= 8: 0x4c else: 0x48), 0x89,
            byte(0x47 or ((hardware and 7) shl 3)), byte(slot*8)]) # MOV [RDI+slot*8],resident64.

    proc emitCheckedReadResidentEntry(code: var X86Block, access: X86CheckedReadAccess) =
      ## Save exactly the selected hardware lanes and initialize mapped reads before first write.
      for slot in 0..12:
        let encoded = access.bank.registers[slot]
        if encoded != 0:
          saveCheckedReadRegister(code, encoded-1)
          loadCheckedReadLiveIn(code, access, slot)
      put(code, [0x49'u8, 0x89, 0xf2]) # MOV R10,RSI saves the extent table.

    proc emitCheckedReadResidentReturn(code: var X86Block, access: X86CheckedReadAccess,
        status: uint32) =
      ## Publish the scalar status and restore the caller's saved registers.
      put(code, [0xb8'u8]) # MOV EAX,status defines the full scalar result.
      cycleWord(code, status)
      restoreCheckedReadRegisters(code, access.bank)
      put(code, [0xc3'u8]) # RET consumes the original caller return RIP.

    proc checkedReadResidentInstructions(body: NativeReadBody, dirty: uint32): seq[byte] =
      var access = X86CheckedReadAccess(bank: x86ResidentAccess(dirty), liveIns: 0, written: 0)
      var code = default(X86Block)
      var fixes: seq[X86CycleFixup] = @[]
      var labels = default(array[1+4*int(NativeReadFactLimit), int])
      var nextLabel = 1'u8
      emitCheckedReadOperations(code, fixes, labels, body, access, body.len, 0, nextLabel)
      assert access.written == dirty
      commitCheckedReadRegisters(code, access.bank)
      emitCheckedReadResidentReturn(code, access, NativeReadSuccess)
      labels[0] = code.bytes.len # Late refusal skips every guest-file store.
      emitCheckedReadResidentReturn(code, access, NativeReadRefusal)

      var entry = default(X86Block)
      emitCheckedReadResidentEntry(entry, access)
      if entry.bytes.len + code.bytes.len > NativeImageByteLimit: return @[]
      # A prepended prologue shifts each branch and its target equally.
      put(entry, sealCheckedRead(code, fixes, labels))
      takeX86Instructions(entry)

    func fitsCheckedReadBank(dirty: uint32): bool =
      ## Select the resident path only when all prospective writes fit the bank.
      var count = 0
      for slot in 0..12:
        if (dirty and (1'u32 shl slot)) != 0: inc count
      count <= X86ResidentHardware.len

    proc x86CheckedReadInstructions*(body: NativeReadBody): seq[byte] =
      assert body.complete and sizeof(RegisterFile) == 104
      # ARM/x86 allocation gap: this bank selects dirty lanes only; read-only live-ins
      # reload canonical slots. Above six dirty lanes we copy all thirteen slots to the stack.
      # ARM retains live-ins and writes in ArmReadSpan's bank. Revisit live-in allocation and
      # sparse/hybrid staging, preserving delayed publication and unchanged-register refusal.
      # Both x86 choices execute native read code.
      let dirty = readBodyDirty(body, body.len)
      if fitsCheckedReadBank(dirty):
        return checkedReadResidentInstructions(body, dirty)
      checkedReadStackInstructions(body, dirty)

    when NativeReadCycleEnabled:
      const
        # Explicit register profiles and the SysV stack witness keep their original lowering.
        readCycleDefaultProfile = not (defined(pvmX86ResidentProof) or
          defined(pvmX86ReadCycleResident) or defined(pvmX86ReadCycleBudgetRegisters) or
          defined(pvmX86ReadCycleRoleRegisters) or defined(pvmX86ReadCycleCredits))
        readCycleUsesResident = readCycleDefaultProfile or defined(pvmX86ReadCycleResident)
        readCycleUsesBudgetRegisters = readCycleDefaultProfile or
          defined(pvmX86ReadCycleBudgetRegisters)
        readCycleUsesRoleRegisters = readCycleDefaultProfile or defined(pvmX86ReadCycleRoleRegisters)
        readCycleUsesCredits = readCycleDefaultProfile or defined(pvmX86ReadCycleCredits)
        readCyclePrepaid = 7'u8
        readCycleUnpaid = 8'u8        # One return label per role in enum order.
        readCyclePaidMiss = 15'u8
        readCycleOutside = 16'u8
        readCycleReturn = 17'u8
        readCycleExactLocal = 18'u8
        readCycleCreditSlow = 18'u8   # One cold entry per role.
        readCycleCreditResume = 25'u8 # The original post-guard boundary per role.
        readCycleCreditExact = 32'u8  # One cold exact check per role.
        readCycleCreditReconstruct = 39'u8
        readCycleCreditReadUnits = 40'u8
        readCycleCreditPublish = 41'u8
        readCycleCreditLocal = 42'u8
        readCycleLocal =
          when readCycleUsesCredits: readCycleCreditLocal
          else: readCycleExactLocal
        readCycleBodyOps = 22
        readCycleSetupOps = 3
        readCycleCreditGasShift = 7'u8
        readCycleCreditSpanShift = 5'u8

      type X86ReadCycleLabels = array[int(readCycleLocal)+4*int(NativeReadFactLimit)+20, int]

      proc readCycleContextOp(code: var X86Block, encoding: openArray[byte], offset: int) =
        ## Context operations use disp32 because the accounting fields follow the extent table.
        put(code, encoding)
        cycleWord(code, uint32(offset))

      proc readCycleSet(code: var X86Block, offset: int, value: uint32) =
        ## The receipt constants fit positive sign-extended imm32 values.
        readCycleContextOp(code, [0x49'u8, 0xc7, 0x82], offset) # MOV qword [R10+offset],imm32.
        cycleWord(code, value)

      proc readCycleBudget(code: var X86Block, fixes: var seq[X86CycleFixup],
          span: byte, price: uint64, unpaid: byte, budgetRegisters: bool) =
        ## Leave the complete original header unpaid if either full reservation cannot fit.
        immediate(code, 0xb8, price)
        if budgetRegisters:
          put(code, [0x49'u8, 0x39, 0xc1]) # CMP R9,RAX.
        else:
          readCycleContextOp(code, [0x49'u8, 0x39, 0x82], NativeCycleGasOffset) # CMP [R10+gas],RAX.
        cycleEdge(code, fixes, 0x82, unpaid)
        if budgetRegisters:
          put(code, [0x49'u8, 0x83, 0xfb, span]) # CMP R11,span.
        else:
          readCycleContextOp(code, [0x49'u8, 0x83, 0xba], NativeCycleRemainingOffset)
          put(code, [span]) # CMP qword [R10+remaining],span.
        cycleEdge(code, fixes, 0x82, unpaid)

      proc readCycleDebit(code: var X86Block, span: byte, price: uint64, budgetRegisters: bool) =
        ## Debit one already-proved complete unit, including an admitted later Read before its guards.
        immediate(code, 0xb8, price)
        if budgetRegisters:
          put(code, [0x49'u8, 0x29, 0xc1, 0x49, 0x83, 0xeb, span]) # SUB R9,RAX; SUB R11,span.
        else:
          readCycleContextOp(code, [0x49'u8, 0x29, 0x82], NativeCycleGasOffset) # SUB [R10+gas],RAX.
          readCycleContextOp(code, [0x49'u8, 0x83, 0xaa], NativeCycleRemainingOffset)
          put(code, [span]) # SUB qword [R10+remaining],span.

      proc readCycleComplete(code: var X86Block, role: NativeCycleRole) =
        ## Record one completed role, or one four-visit Store group.
        readCycleContextOp(code, [0x49'u8, 0xff, 0x82], NativeCycleVisitsOffset+8*ord(role))
        readCycleSet(code, NativeCycleLastOffset, uint32(ord(role)))

      proc readCycleSelect(code: var X86Block, fixes: var seq[X86CycleFixup], header: uint32) =
        ## Every exit supplies the checked header through a common stack epilogue.
        put(code, [0xb8'u8]) # MOV EAX,header.
        cycleWord(code, header)
        cycleEdge(code, fixes, 0, readCycleReturn)

      func readCycleFitsCredits(layout: NativeCycleLayout): bool =
        ## Check each original cost before grouping. This also bounds the emitted immediates.
        for role in NativeCycleRole:
          let group = if role == NativeCycleRole.Store: NativeCycleGroupVisits else: 1'u64
          if layout.sites[role].price > (1'u64 shl readCycleCreditGasShift) div group or
              NativeCycleSpans[role] > (1'u64 shl readCycleCreditSpanShift) div group:
            return false
        true

      proc readCycleLoadBudgets(code: var X86Block) =
        ## The credit path keeps the original unsigned budgets in context until publication.
        readCycleContextOp(code, [0x49'u8, 0x8b, 0x8a], NativeCycleGasOffset) # MOV RCX,[R10+gas].
        readCycleContextOp(code, [0x49'u8, 0x8b, 0x92], NativeCycleRemainingOffset) # MOV RDX,[R10+remaining].

      proc readCycleCreditCount(code: var X86Block) =
        ## R9 = min(gas >> 7, remaining >> 5). Each remaining credit funds a whole role.
        put(code, [0x49'u8, 0x89, 0xc9, 0x49, 0x89, 0xd0]) # MOV R9,RCX; MOV R8,RDX.
        put(code, [0x49'u8, 0xc1, 0xe9, readCycleCreditGasShift]) # SHR R9,gas shift.
        put(code, [0x49'u8, 0xc1, 0xe8, readCycleCreditSpanShift]) # SHR R8,span shift.
        put(code, [0x4d'u8, 0x39, 0xc1, 0x4d, 0x0f, 0x47, 0xc8]) # CMP R9,R8; CMOVA R9,R8.

      proc emitReadCycleCreditSlow(code: var X86Block, fixes: var seq[X86CycleFixup],
          labels: var X86ReadCycleLabels, layout: NativeCycleLayout) =
        ## Cold code owns RCX/RDX (budgets), ESI (selector), R8/R11 (receipt scratch).
        ## The guest bank, RDI, R10, EAX (exit header), and stack stay intact.
        for role in NativeCycleRole:
          # Each hot borrow has a static role identity and enters before the original probe.
          labels[int(readCycleCreditSlow)+ord(role)] = code.bytes.len
          put(code, [0xbe'u8]) # MOV ESI,role.
          cycleWord(code, uint32(ord(role)))
          cycleEdge(code, fixes, 0, readCycleCreditReconstruct)

        labels[int(readCycleCreditReconstruct)] = code.bytes.len
        readCycleLoadBudgets(code)
        for role in NativeCycleRole:
          # Each term and partial sum fits uint64. They sum to exact funded reservations.
          # Low-half IMUL preserves the full unsigned product. Its flags are unused.
          readCycleContextOp(code, [0x4d'u8, 0x8b, 0x82],
            NativeCycleVisitsOffset+8*ord(role)) # MOV R8,[R10+visits].
          if role == NativeCycleRole.Read:
            # A prepaid miss has no visits. Otherwise exempt the first completed Read,
            # unless a later paid miss replaces that exemption with its own reservation.
            put(code, [0x4d'u8, 0x85, 0xc0]) # TEST R8,R8.
            cycleEdge(code, fixes, 0x84, readCycleCreditReadUnits)
            readCycleContextOp(code, [0x49'u8, 0x83, 0xba], NativeCyclePaidReadOffset)
            put(code, [0'u8]) # CMP qword [R10+paidRead],0.
            cycleEdge(code, fixes, 0x85, readCycleCreditReadUnits)
            put(code, [0x49'u8, 0xff, 0xc8]) # DEC R8.
            labels[int(readCycleCreditReadUnits)] = code.bytes.len
          let group = if role == NativeCycleRole.Store: NativeCycleGroupVisits else: 1'u64
          put(code, [0x4d'u8, 0x69, 0xd8]) # IMUL R11,R8,price.
          cycleWord(code, uint32(layout.sites[role].price*group))
          put(code, [0x4c'u8, 0x29, 0xd9]) # SUB RCX,R11.
          put(code, [0x4d'u8, 0x6b, 0xd8, byte(NativeCycleSpans[role]*group)]) # IMUL R11,R8,span.
          put(code, [0x4c'u8, 0x29, 0xda]) # SUB RDX,R11.

        put(code, [0x83'u8, 0xfe, byte(NativeCycleNoCompleted)]) # CMP ESI,exit selector.
        cycleEdge(code, fixes, 0x84, readCycleCreditPublish)
        readCycleCreditCount(code)
        # Consume the current role's credit if available. A zero-credit role can still
        # resume after the exact guard below. Never resume with the unsigned borrow value.
        put(code, [0x45'u8, 0x31, 0xdb, 0x49, 0x83, 0xe9, 1]) # XOR R11D,R11D; SUB R9,1.
        put(code, [0x4d'u8, 0x0f, 0x42, 0xcb]) # CMOVB R9,R11.
        for role in NativeCycleRole:
          put(code, [0x83'u8, 0xfe, byte(ord(role))]) # CMP ESI,role.
          cycleEdge(code, fixes, 0x84, readCycleCreditExact+byte(ord(role)))
        put(code, [0x0f'u8, 0x0b]) # UD2. Only the seven static roles can reach dispatch.
        for role in NativeCycleRole:
          # An unaffordable role returns the same unpaid header without running its probe.
          let label = byte(ord(role))
          labels[int(readCycleCreditExact)+ord(role)] = code.bytes.len
          let group = if role == NativeCycleRole.Store: NativeCycleGroupVisits else: 1'u64
          put(code, [0x48'u8, 0x81, 0xf9]) # CMP RCX,price.
          cycleWord(code, uint32(layout.sites[role].price*group))
          cycleEdge(code, fixes, 0x82, readCycleUnpaid+label)
          put(code, [0x48'u8, 0x83, 0xfa, byte(NativeCycleSpans[role]*group)]) # CMP RDX,span.
          cycleEdge(code, fixes, 0x82, readCycleUnpaid+label)
          cycleEdge(code, fixes, 0, readCycleCreditResume+label)

      proc readCycleCompare(code: var X86Block, access: X86ResidentAccess,
          operation: NativeOperation) =
        ## Capture both original operands for the certified signed or equality branch.
        readAccess(code, access, operation.slots.aIndex, false)
        if operation.opcode <= 90: immediate(code, 0xb9, operation.immediate)
        else: readAccess(code, access, operation.slots.bIndex, true)
        put(code, [0x48'u8, 0x39, 0xc8]) # CMP RAX,RCX.

      proc readCycleCopySlots(code: var X86Block) =
        ## Copy the complete 13-slot register file between the canonical array and private stack.
        put(code, [0xb9'u8]) # MOV ECX,13.
        cycleWord(code, 13)
        put(code, [0xf3'u8, 0x48, 0xa5]) # REP MOVSQ, with SysV's clear direction flag.

      proc readCycleDirtyPage(code: var X86Block, fixes: var seq[X86CycleFixup], unpaid: byte,
          last: bool) =
        ## BT uses the full page index after bounding its containing bitmap word.
        if last: put(code, [0x8d'u8, 0x42, 0x03]) # LEA EAX,[RDX+3]; the end was range-checked.
        else: put(code, [0x89'u8, 0xd0]) # MOV EAX,EDX.
        put(code, [0xc1'u8, 0xe8, 0x0c, 0x89, 0xc1, 0xc1, 0xe9, 0x06]) # page, then word index.
        readCycleContextOp(code, [0x49'u8, 0x3b, 0x8a], NativeCycleDirtyWordsOffset) # CMP RCX,[R10+words].
        cycleEdge(code, fixes, 0x83, unpaid)
        put(code, [0x48'u8, 0x0f, 0xa3, 0x06]) # BT [RSI],RAX.
        cycleEdge(code, fixes, 0x83, unpaid) # JNC when the page is not already dirty.

      proc readCycleAdvance(code: var X86Block, access: X86ResidentAccess,
          slot: range[0..12], delta: byte) =
        ## Apply the original full-width wrapping Store increment to the current lane.
        let encoded = access.registers[slot]
        if encoded == 0:
          put(code, [0x48'u8, 0x83, 0x47, byte(slot*8), delta]) # ADD qword [RDI+slot*8],delta.
        else:
          let hardware = encoded-1
          put(code, [byte(if hardware >= 8: 0x49 else: 0x48), 0x83,
            byte(0xc0 or (hardware and 7)), delta]) # ADD resident64,delta.

      template emitReadCycleStore(code: var X86Block, fixes: var seq[X86CycleFixup],
          labels: untyped, word: NativeCycleWord, span, unpaid: byte, price: uint64,
          nextLabel: var byte, budgetRegisters, credits: bool, access: X86ResidentAccess) =
        ## Preflight the existing checked word projection, then commit exactly one group.
        readAccess(code, access, word.shiftLane, false)
        put(code, [0xa8'u8, 0x1f]) # TEST AL,31: the first extraction must start at bit zero.
        cycleEdge(code, fixes, 0x85, unpaid)
        readAccess(code, access, word.baseLane, false)
        put(code, [0x48'u8, 0x83, 0xc0, 0x04]) # ADD RAX,4 rejects wrapped host-width bases.
        cycleEdge(code, fixes, 0x82, unpaid)
        readAccess(code, access, word.boundLane, true)
        put(code, [0x48'u8, 0x39, 0xc8]) # CMP nextBase,bound; none of the earlier visits can exit.
        cycleEdge(code, fixes, 0x87, unpaid)
        readBodyBase(code, access, word.baseLane)
        put(code, [0x81'u8, 0xc2]) # ADD EDX,disp32 after capturing the old low word.
        cycleWord(code, uint32(word.displacement and 0xffffffff'u64))
        put(code, [0x81'u8, 0xfa]) # CMP EDX,65536.
        cycleWord(code, 65536)
        cycleEdge(code, fixes, 0x82, unpaid)
        put(code, [0x83'u8, 0xfa, 0xfb]) # CMP EDX,0xfffffffb, the checked word upper bound.
        cycleEdge(code, fixes, 0x87, unpaid)

        let accepted = nextLabel
        let rw = nextLabel+1
        nextLabel += 2
        # An address at or above the stack base follows the checked worker's stack priority.
        const stackOffset = byte(NativeCycleWritableOffset)
        const rwOffset = stackOffset+24
        put(code, [0x49'u8, 0x3b, 0x52, stackOffset]) # CMP RDX,[R10+stack.first].
        cycleEdge(code, fixes, 0x82, rw)
        emitCheckedExtent(code, fixes, stackOffset, 4, unpaid, accepted)
        labels[int(rw)] = code.bytes.len
        emitCheckedExtent(code, fixes, rwOffset, 4, unpaid, accepted)
        labels[int(accepted)] = code.bytes.len
        put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX: the writable pointer must exist.
        cycleEdge(code, fixes, 0x84, unpaid)
        put(code, [0x4c'u8, 0x8d, 0x04, 0x01]) # LEA R8,[RCX+RAX] retains the proved writable address.
        readCycleContextOp(code, [0x49'u8, 0x8b, 0xb2], NativeCycleDirtyOffset) # MOV RSI,[R10+dirty].
        put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI.
        cycleEdge(code, fixes, 0x84, unpaid)
        readCycleDirtyPage(code, fixes, unpaid, false)
        # A four-byte aligned write stays in one page. Keep both checks for unaligned words.
        let pagesReady = nextLabel
        inc nextLabel
        put(code, [0xf6'u8, 0xc2, 0x03]) # TEST DL,3.
        cycleEdge(code, fixes, 0x84, pagesReady)
        readCycleDirtyPage(code, fixes, unpaid, true)
        labels[int(pagesReady)] = code.bytes.len

        if not credits: readCycleDebit(code, span, price, budgetRegisters)
        readAccess(code, access, word.valueLane, false)
        put(code, [0x41'u8, 0x89, 0x00, 0xc1, 0xe8, 0x18]) # MOV [R8],EAX; SHR EAX,24.
        writeAccess(code, access, word.byteLane)
        readCycleAdvance(code, access, word.baseLane, 4)
        readCycleAdvance(code, access, word.shiftLane, 32)
        readCycleComplete(code, NativeCycleRole.Store)
        readAccess(code, access, word.baseLane, false)
        readAccess(code, access, word.boundLane, true)
        put(code, [0x48'u8, 0x39, 0xc8]) # Preserve the original != backedge after the fourth visit.
        cycleEdge(code, fixes, 0x85, byte(ord(NativeCycleRole.Store)))

      proc emitReadCycleTailPointer(code: var X86Block, fixes: var seq[X86CycleFixup],
          labels: var X86ReadCycleLabels, address: uint32, slot: byte, nextLabel: var byte) =
        ## Resolve only metadata from this entry's immutable clipped descriptors.
        ## Both a proved pointer and a miss stay local to the leaf's stack frame.
        put(code, [0xba'u8]) # MOV EDX,absolute32.
        cycleWord(code, address)
        let accepted = nextLabel
        let saved = nextLabel+1
        nextLabel += 2
        for region in 0..<3:
          # Preserve the original extent order and require the whole signed word in one extent.
          let nextRegion = nextLabel
          inc nextLabel
          emitCheckedExtent(code, fixes, byte(region*24), 4, nextRegion, accepted)
          labels[int(nextRegion)] = code.bytes.len
        put(code, [0x45'u8, 0x31, 0xc0]) # XOR R8D,R8D records a miss without exiting.
        cycleEdge(code, fixes, 0, saved)
        labels[int(accepted)] = code.bytes.len
        put(code, [0x4c'u8, 0x8d, 0x04, 0x01]) # LEA R8,[RCX+RAX] forms the proved byte address.
        labels[int(saved)] = code.bytes.len
        put(code, [0x4c'u8, 0x89, 0x44, 0x24, slot]) # MOV [RSP+slot],R8.

      func entryReadWindow(cycle: NativeReadCycle): NativeReadWindow =
        ## Admit an entry-local address only if no emitted role writes its base lane.
        ## ARM64 still checks each connected qword against the ordered descriptors at the load.
        result = default(NativeReadWindow)
        let window = nativeReadWindow(cycle.read)
        if window.operations == 0: return
        let base = window.baseLane
        let word = cycle.word
        if (readBodyDirty(cycle.read, cycle.read.len) and (1'u32 shl int(base))) != 0 or
            base in [word.baseLane, word.shiftLane, word.byteLane, cycle.tailLoad.slots.aIndex,
                     cycle.tailStep.slots.destinationIndex, cycle.outer[0].slots.destinationIndex,
                     cycle.outer[1].slots.destinationIndex]: return
        result = window

      proc emitEntryReadWindow(code: var X86Block, fixes: var seq[X86CycleFixup],
          labels: var X86ReadCycleLabels, window: NativeReadWindow, bank: X86ResidentAccess,
          slot: byte, nextLabel: var byte) =
        ## Cache the first descriptor's pointer only. A miss selects the full ordered search.
        let accepted = nextLabel
        let save = nextLabel+1
        nextLabel += 2
        put(code, [0x31'u8, 0xf6]) # XOR ESI,ESI records a miss.
        readBodyBase(code, bank, window.baseLane)
        put(code, [0x81'u8, 0xc2]) # ADD EDX,first wraps the window start modulo 2^32.
        cycleWord(code, window.first)
        put(code, [0x81'u8, 0xfa]) # CMP EDX,max32-39 prevents wrap inside the window.
        cycleWord(code, high(uint32)-39'u32)
        cycleEdge(code, fixes, 0x87, save)
        emitCheckedExtent(code, fixes, 0, 40, save, accepted)
        labels[int(accepted)] = code.bytes.len
        put(code, [0x48'u8, 0x85, 0xc9]) # TEST RCX,RCX.
        cycleEdge(code, fixes, 0x84, save)
        put(code, [0x48'u8, 0x8d, 0x34, 0x01]) # LEA RSI,[RCX+RAX].
        labels[int(save)] = code.bytes.len
        put(code, [0x48'u8, 0x89, 0x74, 0x24, slot]) # MOV [RSP+slot],RSI.

      proc emitResidentCycleRead(code: var X86Block, fixes: var seq[X86CycleFixup],
          labels: var X86ReadCycleLabels, body: NativeReadBody, bank: X86ResidentAccess,
          dirty: uint32, nextLabel: var byte) =
        ## Derive live-ins while emitting the guarded body, then prepend each Read's reloads.
        var access = X86CheckedReadAccess(bank: bank)
        var read = default(X86Block)
        var readFixes: seq[X86CycleFixup] = @[]
        let firstLabel = nextLabel
        emitCheckedReadOperations(read, readFixes, labels, body, access, readCycleBodyOps,
          readCyclePaidMiss, nextLabel)
        assert access.written == dirty
        for slot in 0..12:
          # A later Read must observe the canonical state left by the previous roles.
          loadCheckedReadLiveIn(code, access, slot)
        let bodyStart = code.bytes.len
        put(code, read.bytes)
        for label in int(firstLabel)..<int(nextLabel):
          # The other labels, including the common paid-miss edge, are image-relative already.
          labels[label] += bodyStart
        for fix in readFixes:
          fixes.add(X86CycleFixup(at: bodyStart+fix.at, target: fix.target))
        commitCheckedReadRegisters(code, bank)

      proc emitX86ReadCycle(cycle: NativeReadCycle, allowCredits, allowWindow: bool): seq[byte] =
        ## Lower the certified seven-role graph with a private checkpoint for each transactional Read.
        ## ARM retains all guest lanes across roles. The x86 role bank retains only the Read
        ## writes and Store base. Other lanes stay canonical, including writes outside Read.
        ## The synchronous leaf owns the canonical file until return. Its mapped Read slots
        ## hold the pre-Read checkpoint while the hardware bank holds current guest state.
        assert sizeof(RegisterFile) == 104 and sizeof(NativeCycleContext) == NativeCycleContextBytes
        if not cycle.read.complete or cycle.read.continuationInfo.terminal == 0 or
            cycle.read.len != readCycleBodyOps+readCycleSetupOps or
            cycle.tailLoad.opcode != 57 or cycle.tailStep.opcode != 131 or
                cycle.tailBranch.opcode != 173 or
            cycle.outer[0].opcode != 131 or cycle.outer[1].opcode != 149 or cycle.outer[2].opcode !=
                81 or
            cycle.gate.opcode != 88: return @[]
        let word = cycle.word
        let lanes = [word.valueLane, word.shiftLane, word.byteLane, word.baseLane, word.boundLane]
        for i in 0..<lanes.len:
          for j in 0..<i:
            if lanes[i] == lanes[j]: return @[]
        if cycle.layout.sites[NativeCycleRole.Store].price > high(
            uint64) div NativeCycleGroupVisits:
          return @[]
        for index in 0..<readCycleBodyOps:
          # Standalone certificates now admit absolute loads. The connected Read stays relative.
          let opcode = cycle.read.operation(index).opcode
          if nativeReadEncodingOpcode(opcode) != opcode: return @[]

        let dirty = readBodyDirty(cycle.read, readCycleBodyOps)
        let resident = readCycleUsesResident and fitsCheckedReadBank(dirty)
        let budgetRegisters = resident and readCycleUsesBudgetRegisters
        let roleMask = dirty or (1'u32 shl int(word.baseLane))
        let roleRegisters = budgetRegisters and readCycleUsesRoleRegisters and
          fitsCheckedReadBank(roleMask)
        # The opt-off build retains the original label array and reservation emitter.
        let credits =
          when readCycleUsesCredits:
            allowCredits and roleRegisters and readCycleFitsCredits(cycle.layout)
          else:
            false
        let bank = if roleRegisters: x86ResidentAccess(roleMask)
          elif resident: x86ResidentAccess(dirty) else: default(X86ResidentAccess)
        let roleAccess = if roleRegisters: bank else: default(X86ResidentAccess)
        # Keep the entry-local borrow outside the 104-byte stack checkpoint.
        # Both allocations preserve the original alignment and fit a signed immediate.
        let tailSlot = if resident: 0'u8 else: byte(sizeof(RegisterFile))
        let stackBytes = tailSlot+16'u8
        var code = default(X86Block)
        var fixes: seq[X86CycleFixup] = @[]
        var labels = default(X86ReadCycleLabels)
        var nextLabel = readCycleLocal
        let window = if allowWindow and roleRegisters: entryReadWindow(cycle)
          else: default(NativeReadWindow)
        let slowRead = nextLabel
        let readComplete = nextLabel+1
        if window.operations != 0: nextLabel += 2
        if resident:
          for slot in 0..12:
            let encoded = bank.registers[slot]
            if encoded != 0:
              # Save each selected SysV lane once. Prepaid Read already has a checkpoint.
              saveCheckedReadRegister(code, encoded-1)
              if roleRegisters: loadCheckedReadRegister(code, bank, slot)
        else:
          # R11 retains the canonical pointer while RDI addresses the private stack stage.
          put(code, [0x49'u8, 0x89, 0xfb]) # MOV R11,RDI.
        put(code, [0x48'u8, 0x83, 0xec, stackBytes]) # SUB RSP,stackBytes.
        put(code, [0x49'u8, 0x89, 0xf2]) # R10=RSI holds the context, RDI stays canonical.
        # Extent checks use RCX/RDX before either live budget ledger is loaded.
        emitReadCycleTailPointer(code, fixes, labels,
          uint32(cycle.tailLoad.immediate and 0xffffffff'u64), tailSlot, nextLabel)
        if window.operations != 0:
          # The second pointer fits beside the Tail pointer in the existing resident frame.
          emitEntryReadWindow(code, fixes, labels, window, bank, tailSlot+8, nextLabel)
        if credits:
          # R9 funds paid roles. The first Read bypasses it because the checked header paid.
          readCycleLoadBudgets(code)
          readCycleCreditCount(code)
        elif budgetRegisters:
          # R9/R11 belong to the resident ledger across all roles. Keep scalar and guard scratch
          # out of them. The stack path needs R11 for its canonical pointer.
          readCycleContextOp(code, [0x4d'u8, 0x8b, 0x8a], NativeCycleGasOffset) # MOV R9,[R10+gas].
          readCycleContextOp(code, [0x4d'u8, 0x8b, 0x9a], NativeCycleRemainingOffset) # MOV R11,[R10+remaining].
        put(code, [0x31'u8, 0xc0]) # XOR EAX,EAX initializes the receipt.
        for role in NativeCycleRole:
          readCycleContextOp(code, [0x49'u8, 0x89, 0x82], NativeCycleVisitsOffset+8*ord(role))
        readCycleContextOp(code, [0x49'u8, 0x89, 0x82], NativeCyclePaidReadOffset)
        readCycleSet(code, NativeCycleLastOffset, uint32(NativeCycleNoCompleted))
        cycleEdge(code, fixes, 0, readCyclePrepaid)

        for role in NativeCycleRole:
          let label = byte(ord(role))
          let unpaid = readCycleUnpaid+label
          labels[int(label)] = code.bytes.len
          let group = if role == NativeCycleRole.Store: NativeCycleGroupVisits else: 1'u64
          let span = byte(NativeCycleSpans[role]*group)
          let price = cycle.layout.sites[role].price*group
          if credits:
            # A funded credit covers both reservations. Cold checks enter at this same
            # boundary, before Store/Tail preflight and before a later Read checkpoint.
            put(code, [0x49'u8, 0x83, 0xe9, 1]) # SUB R9,1.
            cycleEdge(code, fixes, 0x82, readCycleCreditSlow+label)
            labels[int(readCycleCreditResume)+ord(role)] = code.bytes.len
          else:
            readCycleBudget(code, fixes, span, price, unpaid, budgetRegisters)
          case role
          of NativeCycleRole.Read:
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            if roleRegisters:
              # Save only the lanes this paid Read can replace. Earlier stores survive a miss.
              commitCheckedReadRegisters(code, bank, dirty)
            labels[int(readCyclePrepaid)] = code.bytes.len # The checked entry already reserved the first Read.
            if roleRegisters:
              if window.operations != 0:
                # Select one whole Read body, leaving the original search off the hit path.
                put(code, [0x48'u8, 0x8b, 0x74, 0x24, tailSlot+8]) # MOV RSI,[RSP+slot].
                put(code, [0x48'u8, 0x85, 0xf6]) # TEST RSI,RSI.
                cycleEdge(code, fixes, 0x84, slowRead)
              emitCheckedReadOperations(code, fixes, labels, cycle.read, roleAccess,
                readCycleBodyOps, readCyclePaidMiss, nextLabel, window)
              if window.operations != 0: labels[int(readComplete)] = code.bytes.len
            elif resident:
              emitResidentCycleRead(code, fixes, labels, cycle.read, bank, dirty, nextLabel)
            else:
              put(code, [0x4c'u8, 0x89, 0xde, 0x48, 0x89, 0xe7]) # RSI=R11, RDI=RSP.
              readCycleCopySlots(code)
              put(code, [0x48'u8, 0x89, 0xe7]) # RDI=RSP for all scalar and load writes in the stage.
              emitCheckedReadOperations(code, fixes, labels, cycle.read, X86CanonicalAccess(),
                readCycleBodyOps, readCyclePaidMiss, nextLabel)
              put(code, [0x48'u8, 0x89, 0xe6, 0x4c, 0x89, 0xdf]) # RSI=RSP, RDI=R11.
              readCycleCopySlots(code)
              put(code, [0x4c'u8, 0x89, 0xdf]) # RDI=R11 resumes canonical writes at the role boundary.
            readCycleComplete(code, role)
          of NativeCycleRole.StoreSetup:
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            for index in readCycleBodyOps..<readCycleBodyOps+readCycleSetupOps:
              let op = cycle.read.operation(index)
              emitX86OperationAccess(code, roleAccess, op.opcode, op.slots, op.immediate)
            readCycleComplete(code, role)
          of NativeCycleRole.Store:
            emitReadCycleStore(code, fixes, labels, word, span, unpaid, price, nextLabel,
              budgetRegisters, credits, roleAccess)
          of NativeCycleRole.Tail:
            # A missing pointer leaves this affordable role unpaid. Load fresh bytes
            # on every visit so earlier Stores remain visible, including aliases.
            put(code, [0x4c'u8, 0x8b, 0x44, 0x24, tailSlot]) # MOV R8,[RSP+slot].
            put(code, [0x4d'u8, 0x85, 0xc0]) # TEST R8,R8.
            cycleEdge(code, fixes, 0x84, unpaid)
            put(code, [0x49'u8, 0x63, 0x00]) # MOVSXD RAX,dword [R8].
            writeAccess(code, roleAccess, cycle.tailLoad.slots.aIndex)
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            let step = cycle.tailStep
            emitX86OperationAccess(code, roleAccess, step.opcode, step.slots, step.immediate)
            readCycleComplete(code, role)
            readCycleCompare(code, roleAccess, cycle.tailBranch)
            cycleEdge(code, fixes, 0x8c, byte(ord(NativeCycleRole.StoreSetup))) # JL signed.
          of NativeCycleRole.Jump:
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            readCycleComplete(code, role)
          of NativeCycleRole.Outer:
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            for index in 0..1:
              let op = cycle.outer[index]
              emitX86OperationAccess(code, roleAccess, op.opcode, op.slots, op.immediate)
            readCycleComplete(code, role)
            readCycleCompare(code, roleAccess, cycle.outer[2])
            cycleEdge(code, fixes, 0x84, readCycleOutside) # JE.
          of NativeCycleRole.Gate:
            if not credits: readCycleDebit(code, span, price, budgetRegisters)
            readCycleComplete(code, role)
            readCycleCompare(code, roleAccess, cycle.gate)
            cycleEdge(code, fixes, 0x8e, byte(ord(NativeCycleRole.Outer))) # JLE signed.
            cycleEdge(code, fixes, 0, byte(ord(NativeCycleRole.Read)))

        for role in NativeCycleRole:
          labels[int(readCycleUnpaid)+ord(role)] = code.bytes.len
          readCycleSelect(code, fixes, cycle.layout.sites[role].header)
        labels[int(readCyclePaidMiss)] = code.bytes.len
        if roleRegisters:
          # Discard only this Read's speculative writes before the common publication.
          for slot in 0..12:
            if (dirty and (1'u32 shl slot)) != 0:
              loadCheckedReadRegister(code, bank, slot)
        # The Read-only and stack banks discard their stage by skipping its commit.
        readCycleSet(code, NativeCyclePaidReadOffset, 1)
        readCycleSelect(code, fixes, cycle.layout.sites[NativeCycleRole.Read].header)
        labels[int(readCycleOutside)] = code.bytes.len
        readCycleSelect(code, fixes, cycle.layout.outsideHeader)
        labels[int(readCycleReturn)] = code.bytes.len
        if credits:
          # A refused Store or Tail may have borrowed a credit but has no completed visit.
          # Reconstruct before publication using only completed visits and the paid Read flag.
          put(code, [0xbe'u8]) # MOV ESI,exit selector.
          cycleWord(code, uint32(NativeCycleNoCompleted))
          cycleEdge(code, fixes, 0, readCycleCreditReconstruct)
          labels[int(readCycleCreditPublish)] = code.bytes.len
          readCycleContextOp(code, [0x49'u8, 0x89, 0x8a], NativeCycleGasOffset) # MOV [R10+gas],RCX.
          readCycleContextOp(code, [0x49'u8, 0x89, 0x92], NativeCycleRemainingOffset) # MOV [R10+remaining],RDX.
        if roleRegisters:
          # Publish the completed prefix before the caller validates the last role's predicate.
          commitCheckedReadRegisters(code, bank)
        if budgetRegisters and not credits:
          # All exits publish the same full-width budgets without clobbering the header in EAX.
          readCycleContextOp(code, [0x4d'u8, 0x89, 0x8a], NativeCycleGasOffset) # MOV [R10+gas],R9.
          readCycleContextOp(code, [0x4d'u8, 0x89, 0x9a], NativeCycleRemainingOffset) # MOV [R10+remaining],R11.
        put(code, [0x48'u8, 0x83, 0xc4, stackBytes]) # ADD RSP,stackBytes releases the borrow.
        if resident: restoreCheckedReadRegisters(code, bank)
        put(code, [0xc3'u8]) # RET preserves the checked header in EAX.
        if credits: emitReadCycleCreditSlow(code, fixes, labels, cycle.layout)
        if window.operations != 0:
          # Run the same original operations after the original checkpoint and debit.
          labels[int(slowRead)] = code.bytes.len
          emitCheckedReadOperations(code, fixes, labels, cycle.read, roleAccess,
            readCycleBodyOps, readCyclePaidMiss, nextLabel)
          cycleEdge(code, fixes, 0, readComplete)
        if code.bytes.len > NativeImageByteLimit: return @[]
        for fix in fixes:
          # The complete image ceiling proves signed rel32 for both forward and backward edges.
          let delta = cast[uint32](int32(labels[int(fix.target)]-(fix.at+4)))
          for shift in 0..<4:
            code.bytes[fix.at+shift] = byte((delta shr (shift*8)) and 255)
        takeX86Instructions(code)

      proc x86ReadCycleInstructions*(cycle: NativeReadCycle): seq[byte] {.inline.} =
        ## Ordinary x86 uses register budgets and credits for eligible connected cycles.
        ## The Read and role masks must fit the bank, and every role must fit one credit.
        ## Both x86 and ARM publish the same checked receipt for all seven roles.
        when readCycleUsesCredits:
          result = emitX86ReadCycle(cycle, true, true)
          if result.len == 0:
            # Preserve the original credited image if only the extra Read body exceeds the cap.
            result = emitX86ReadCycle(cycle, true, false)
          if result.len != 0: return
        # Preserve the original exact image under the same ceiling.
        result = emitX86ReadCycle(cycle, false, true)
        if result.len == 0: result = emitX86ReadCycle(cycle, false, false)

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
