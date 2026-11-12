# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone JamV1 interpreter: mutable instance, parallel handler/Args vectors,
## lazy block compilation and patched jump handlers from pinned interpreter.rs.
## This experiment supports Full(L2Hit), synchronous gas, unlimited code cache,
## and standard/dynamic memory. Debug tracing and other ISAs are not exposed.

import std/[assertions, bitops]
import ./[program, decode, simulator, operations, compiled_offsets, plain_vector,
  standard_memory, dynamic_memory, memory_layout]
export program, standard_memory, dynamic_memory

type
  Module* = ref object
    ## Immutable admitted program and layout shared by mutable instances.
    blob: ProgramBlob
    layout: MemoryLayout
    dynamic, metered: bool
  ModuleError* {.pure.} = enum
    ## Admission separates invalid instruction streams from invalid memory geometry.
    InvalidCode, InvalidLayout
  ModuleResult* = object
    ## Failed/default admission has no instance-constructible module payload.
    case success: bool
    of true: value: Module
    of false:
      reason: ModuleError
      invalidPc: uint32
  HostError* {.pure.} = enum
    ## Public host-memory error categories; success carries no hidden state publication.
    None, OutOfRange, AllocationLimit, DynamicRequired, Unaligned
  InterruptKind* {.pure.} = enum
    ## Source run outcomes supported by the experiment's configuration.
    Finished, Trap, Ecalli, NotEnoughGas, Segfault
  Interrupt* = object
    ## Scalar interruption payload; memory remains owned by the instance.
    kind*: InterruptKind
    hostcall*, page*, pageSize*: uint32
    readOnly*: bool
  Args = array[4, uint32]
    ## Exact sixteen-byte source argument record.
  Handler = proc(instance: var Instance, offset: uint32): uint32 {.nimcall.}
    ## Non-closure function pointer, matching ordinary upstream handler dispatch.
  Instance* = object
    ## One mutable machine, including retained memory and lazily populated code caches.
    module*: Module
    standard*: StandardMemory
    dynamic*: DynamicMemory
    regs*: array[13, uint64]
    pc*, nextPc*: uint32
    pcValid*, nextPcValid*: bool
    nextPcChanged, chargeGasOnEntry: bool
    gas*: int64
    offsets: CompiledOffsets
    handlers: PlainVector[Handler]
    args: PlainVector[Args]
    nextCompiled: uint32
    interrupt: Interrupt

proc ok*(answer: ModuleResult): bool {.inline.} =
  ## Inspect admission without exposing an invalid payload.
  answer.success

proc module*(answer: ModuleResult): Module =
  ## Retain a successfully admitted immutable module owner.
  assert answer.success
  answer.value

proc error*(answer: ModuleResult): ModuleError =
  ## Read the failure category only after failed admission.
  assert not answer.success
  answer.reason

proc invalidPc*(answer: ModuleResult): uint32 =
  ## Return the first invalid instruction's offset, or zero for a layout failure.
  assert not answer.success
  answer.invalidPc

proc memoryLayout*(module: Module): MemoryLayout =
  ## Expose geometry and immutable initial-data owners for host fixture restoration.
  module.layout

proc newModule*(blob: ProgramBlob, dynamic: bool, pageSize: uint32 = 4096,
    auxSize: uint32 = 0, metered: bool = true): ModuleResult =
  ## Match the selected upstream profile: validate JamV1 before memory-map admission.
  let invalid = validateCode(blob.code.view(), blob.mask.view())
  if invalid != high(uint32):
    return ModuleResult(success: false, reason: ModuleError.InvalidCode, invalidPc: invalid)
  let geometry = buildLayout(pageSize, blob.parts.roSize, blob.parts.rwSize,
    blob.parts.stackSize, auxSize, blob.parts.ro, blob.parts.rw)
  if not geometry.ok:
    return ModuleResult(success: false, reason: ModuleError.InvalidLayout)
  ModuleResult(success: true, value: Module(blob: blob, layout: geometry.layout,
    dynamic: dynamic, metered: metered))

proc compileBlock(instance: var Instance, pc: uint32): uint32
  ## Compile one block lazily; high(uint32) denotes an absent target.

proc resolveJump(instance: var Instance, pc: uint32): uint32
  ## Resolve a validated in-program jump into a compiled handler index.

proc signed32(value: uint32): uint64 {.inline.} =
  ## Source get/set_i32 sign extension represented as register bits.
  cast[uint64](int64(cast[int32](value)))

proc swap64(value: uint64): uint64 {.inline.} =
  ## Source swap_bytes lowered through the compiler byte-swap primitive.
  proc swap(value: uint64): uint64 {.importc: "__builtin_bswap64", nodecl.}
  swap(value)

proc stop(instance: var Instance, interrupt: Interrupt): uint32 {.inline.} =
  ## Return the source out-of-range dispatch sentinel after recording the interrupt.
  instance.interrupt = interrupt
  high(uint32)

proc trap(instance: var Instance, pc: uint32): uint32 =
  ## Preserve the faulting PC and clear any runnable continuation.
  instance.pc = pc
  instance.pcValid = true
  instance.nextPcValid = false
  instance.nextPcChanged = true
  instance.stop(Interrupt(kind: InterruptKind.Trap))

proc emit(instance: var Instance, handler: Handler, args: Args) {.inline.} =
  ## Keep the source's separate parallel vectors; no instruction objects survive lowering.
  instance.handlers.add(handler)
  instance.args.add(args)

proc patch(instance: var Instance, offset: uint32, handler: Handler, args: Args) {.inline.} =
  ## Replace a first-use resolver with its resolved source handler and arguments.
  instance.handlers[int(offset)] = handler
  instance.args[int(offset)] = args

proc chargeGas(instance: var Instance, offset: uint32): uint32 =
  ## Sync exhaustion preserves gas and resumes at this exact charge handler.
  let args = instance.args[int(offset)]
  # Nimony wrapping arithmetic matches the pinned Rust release handler subtraction.
  let newGas = instance.gas - int64(args[1])
  if newGas < 0:
    instance.pc = args[0]
    instance.pcValid = true
    instance.nextPc = args[0]
    instance.nextPcValid = true
    instance.nextPcChanged = false
    instance.nextCompiled = offset
    return instance.stop(Interrupt(kind: InterruptKind.NotEnoughGas))
  instance.gas = newGas
  offset + 1

proc trapHandler(instance: var Instance, offset: uint32): uint32 =
  ## Explicit invalid/trap instructions use the same source PC-bearing trap handler.
  instance.trap(instance.args[int(offset)][0])

proc fallthroughHandler(instance: var Instance, offset: uint32): uint32 =
  ## A resolved adjacent block needs only incrementing the compiled cursor.
  offset + 1

proc jumpHandler(instance: var Instance, offset: uint32): uint32 =
  ## A resolved nonadjacent target is stored directly in Args.
  instance.args[int(offset)][0]

proc ecalliHandler(instance: var Instance, offset: uint32): uint32 =
  ## Match source re-decoding of the host call continuation, without publishing memory.
  let args = instance.args[int(offset)]
  let nextPc = block:
    let code = instance.module.blob.code.view()
    let mask = instance.module.blob.mask.view()
    var cursor = initCursor(mask, code.len, args[0], true)
    var instruction = default(ParsedInstruction)
    assert cursor.next(code, mask, instruction)
    instruction.nextOffset
  instance.pc = args[0]
  instance.pcValid = true
  instance.nextPc = nextPc
  instance.nextPcValid = true
  instance.nextPcChanged = true
  instance.nextCompiled = offset + 1
  instance.stop(Interrupt(kind: InterruptKind.Ecalli, hostcall: args[1]))

proc resolveFallthrough(instance: var Instance, pc: uint32): uint32 =
  ## Fallthrough accepts a missing target for compilation but rejects cached invalid boundaries.
  let cached = instance.offsets.get(pc)
  if cached.present:
    return if cached.validJump: cached.target else: high(uint32)
  instance.compileBlock(pc)

proc unresolvedJump[Fallthrough: static[bool]](instance: var Instance, offset: uint32): uint32 =
  ## Resolve only on first execution, then patch to the source adjacent/nonadjacent variant.
  let args = instance.args[int(offset)]
  let target = when Fallthrough: instance.resolveFallthrough(args[1])
    else: instance.resolveJump(args[1])
  if target == high(uint32): return instance.trap(args[0])
  if target == offset + 1:
    instance.patch(offset, fallthroughHandler, default(Args))
  else:
    instance.patch(offset, jumpHandler, [target, 0'u32, 0, 0])
  target

proc loadJump(instance: var Instance, offset: uint32): uint32 =
  ## Resolved load-immediate/jump retains both effects in one source handler.
  let args = instance.args[int(offset)]
  instance.regs[int(args[0])] = signed32(args[1])
  args[2]

proc unresolvedLoadJump(instance: var Instance, offset: uint32): uint32 =
  ## Source writes the register before discovering an invalid jump target.
  let args = instance.args[int(offset)]
  instance.regs[int(args[1])] = signed32(args[2])
  let target = instance.resolveJump(args[3])
  if target == high(uint32): return instance.trap(args[0])
  instance.patch(offset, loadJump, [args[1], args[2], target, 0'u32])
  target

proc indirect(instance: var Instance, pc, address: uint32): uint32 =
  ## Decode the source even dynamic address or return-to-host sentinel.
  if address == 0xffff0000'u32:
    instance.pc = high(uint32)
    instance.pcValid = false
    instance.nextPcValid = false
    instance.nextPcChanged = true
    return instance.stop(Interrupt(kind: InterruptKind.Finished))
  if address == 0 or (address and 1) != 0: return instance.trap(pc)
  var targetPc = 0'u32
  block:
    let width = int(instance.module.blob.jumpWidth)
    let index = int((address - 2) div 2)
    let bytes = instance.module.blob.jumpTable.view()
    if width == 0 or index >= bytes.len div width:
      targetPc = high(uint32)
    else:
      for byteIndex in 0..<width:
        targetPc = targetPc or (uint32(bytes[index * width + byteIndex]) shl (8 * byteIndex))
  if targetPc == high(uint32): return instance.trap(pc)
  let target = instance.resolveJump(targetPc)
  if target == high(uint32): instance.trap(pc) else: target

proc indirectHandler(instance: var Instance, offset: uint32): uint32 =
  ## Add the wrapping guest base/offset before resolving a dynamic jump address.
  let args = instance.args[int(offset)]
  instance.indirect(args[0], uint32(instance.regs[int(args[1])]) + args[2])

proc loadIndirectHandler(instance: var Instance, offset: uint32): uint32 =
  ## Capture the old base before writing a possibly aliasing destination register.
  let args = instance.args[int(offset)]
  let destination = int(args[1] and 15)
  let base = int(args[1] shr 4)
  let address = uint32(instance.regs[base]) + args[3]
  instance.regs[destination] = signed32(args[2])
  instance.indirect(args[0], address)

proc memoryFault(instance: var Instance, offset: uint32, access: Access): uint32 =
  ## Source guest limits trap; mapped faults below 64KiB also trap rather than page-fault.
  if access.kind != AccessKind.Segfault or access.page < 65536:
    return instance.trap(instance.pc)
  instance.pcValid = true
  instance.nextPc = instance.pc
  instance.nextPcValid = true
  instance.nextCompiled = offset
  instance.stop(Interrupt(kind: InterruptKind.Segfault, page: access.page,
    pageSize: instance.module.layout.pageSize, readOnly: access.readOnly))

include ./engine_scalar
include ./engine_branches
include ./engine_lowering

proc resolveJump(instance: var Instance, pc: uint32): uint32 =
  ## JamV1 validates source bitmask boundaries before compiling an uncached target.
  let cached = instance.offsets.get(pc)
  if cached.present:
    return if cached.validJump: cached.target else: high(uint32)
  if not validJump(instance.module.blob.code.view(), instance.module.blob.mask.view(), pc):
    return high(uint32)
  instance.compileBlock(pc)

proc compileBlock(instance: var Instance, pc: uint32): uint32 {.noinline.} =
  ## Build only the reached basic block, calculating Full(L2Hit) gas during lowering.
  if int(pc) >= instance.module.blob.code.len: return high(uint32)
  let blob = instance.module.blob
  let code = blob.code.view()
  let mask = blob.mask.view()
  let origin = uint32(instance.handlers.len)
  if not instance.offsets.allocated: instance.offsets.allocate(uint32(code.len) + 1)
  var jumpTarget = validJump(code, mask, pc)
  var cursor = initCursor(mask, code.len, pc, true)
  var gasVisitor = newSimulator(code)
  var instruction = default(ParsedInstruction)
  var chargeIndex = -1
  while cursor.next(code, mask, instruction):
    instance.offsets.insert(instruction.offset, uint32(instance.handlers.len), jumpTarget)
    jumpTarget = false
    if instance.module.metered:
      if chargeIndex < 0:
        chargeIndex = instance.handlers.len
        instance.emit(chargeGas, [instruction.offset, 0'u32, 0, 0])
      gasVisitor.visit(instruction)
    instance.lower(instruction)
    if instruction.instruction.opcode.startsBlock: break
  if chargeIndex >= 0:
    var cost = 0'u32
    assert gasVisitor.takeBlockCost(cost)
    instance.args[chargeIndex] = [pc, cost, 0'u32, 0]
  if uint32(instance.handlers.len) == origin: high(uint32) else: origin

proc targetAndGas(instance: Instance, cached: CompiledOffset): tuple[target: uint32, cost: int64] =
  ## External jumps into a block pay the whole block unless resuming an existing invocation.
  if cached.validJump or not instance.module.metered or not instance.chargeGasOnEntry:
    return (cached.target, 0'i64)
  var start = int(cached.target)
  while start > 0 and instance.handlers[start] != chargeGas: start -= 1
  assert instance.handlers[start] == chargeGas
  (cached.target, int64(instance.args[start][1]))

proc arbitraryJump(instance: var Instance, pc: uint32): tuple[target: uint32, cost: int64] =
  ## Admit external instruction boundaries and reject interiors of encoded operands.
  let cached = instance.offsets.get(pc)
  if cached.present: return instance.targetAndGas(cached)
  let start = enclosingBlock(instance.module.blob.code.view(), instance.module.blob.mask.view(), pc)
  if start == high(uint32): return (high(uint32), 0'i64)
  if not instance.offsets.get(start).present:
    if instance.compileBlock(start) == high(uint32): return (high(uint32), 0'i64)
  let compiled = instance.offsets.get(pc)
  if not compiled.present: return (high(uint32), 0'i64)
  if start == pc: (compiled.target, 0'i64) else: instance.targetAndGas(compiled)

proc setNextPc*(instance: var Instance, pc: uint32) =
  ## Public host redirection re-enables whole-block gas charging on entry.
  instance.pcValid = false
  instance.nextPc = pc
  instance.nextPcValid = true
  instance.nextPcChanged = true
  instance.chargeGasOnEntry = true

proc newInstance*(module: Module): Instance =
  ## One retained instance owns both source memory variants and an initially empty code cache.
  var instance = Instance(module: module, pc: high(uint32), nextPcChanged: true,
    chargeGasOnEntry: true)
  if module.dynamic: instance.dynamic.reset(module.layout.pageSize)
  else: instance.standard = newStandardMemory(module.layout)
  move(instance)

proc resetMemory*(instance: var Instance) =
  ## Restore memory while retaining the compiled handler cache across invocations.
  if instance.module.dynamic: instance.dynamic.reset(instance.module.layout.pageSize)
  else: instance.standard.reset(instance.module.layout)

proc cacheBytes*(instance: Instance): uint64 =
  ## Initialized source handler/Args entry bytes, excluding capacity and the PC map.
  uint64(instance.handlers.len) * 24

proc run*(instance: var Instance): Interrupt {.noinline.} =
  ## Ordinary source function-pointer dispatch; host interruption returns this same mutable instance.
  if instance.nextPcChanged:
    assert instance.nextPcValid, "next program counter is not set"
    let entry = instance.arbitraryJump(instance.nextPc)
    if entry.target == high(uint32):
      instance.pc = instance.nextPc
      instance.pcValid = true
      return Interrupt(kind: InterruptKind.Trap)
    if entry.cost > instance.gas: return Interrupt(kind: InterruptKind.NotEnoughGas)
    instance.gas -= entry.cost
    instance.nextCompiled = entry.target
    instance.pc = instance.nextPc
    instance.nextPcValid = false
    instance.nextPcChanged = false
    instance.chargeGasOnEntry = false
  var offset = instance.nextCompiled
  while int(offset) < instance.handlers.len:
    let handler = instance.handlers[int(offset)]
    offset = handler(instance, offset)
  instance.interrupt

proc readMemory*(instance: var Instance, address: uint32, output: var openArray[byte]): HostError =
  ## Empty reads always succeed; nonempty reads exclude low memory and crossing 2^32.
  if output.len == 0: return HostError.None
  if address < 65536 or uint64(output.len) > 0x100000000'u64 - uint64(address):
    return HostError.OutOfRange
  let success = if instance.module.dynamic: instance.dynamic.read(address, output)
    else: instance.standard.read(address, output)
  if success: HostError.None else: HostError.OutOfRange

proc writeMemory*(instance: var Instance, address: uint32, input: openArray[byte]): HostError =
  ## Host writes mutate the retained memory directly after public range validation.
  if input.len == 0: return HostError.None
  if address < 65536 or uint64(input.len) > 0x100000000'u64 - uint64(address):
    return HostError.OutOfRange
  if instance.module.dynamic:
    return if instance.dynamic.write(address, input): HostError.None else: HostError.OutOfRange
  let status = instance.standard.write(address, input)
  if status == AccessKind.Ok: HostError.None
  elif status == AccessKind.MemoryLimit: HostError.AllocationLimit
  else: HostError.OutOfRange

proc zeroMemory*(instance: var Instance, address, length: uint32): HostError =
  ## Zero an existing writable range; the private implementation preflights before mutation.
  if length == 0: return HostError.None
  if address < 65536 or uint64(length) > 0x100000000'u64 - uint64(address):
    return HostError.OutOfRange
  if instance.module.dynamic:
    return if instance.dynamic.zero(address, length): HostError.None else: HostError.OutOfRange
  let status = instance.standard.zero(address, length)
  if status == AccessKind.Ok: HostError.None
  elif status == AccessKind.MemoryLimit: HostError.AllocationLimit
  else: HostError.OutOfRange

proc mapZeroMemory*(instance: var Instance, address, length: uint32, readOnly: bool): HostError =
  ## Dynamic mapping requires an aligned start and rounds the requested length up to pages.
  if not instance.module.dynamic: return HostError.DynamicRequired
  if length == 0: return HostError.None
  let mask = instance.module.layout.pageSize - 1
  if (address and mask) != 0: return HostError.Unaligned
  if address < 65536 or uint64(length) > 0x100000000'u64 - uint64(address):
    return HostError.OutOfRange
  let rounded = (length + mask) and not mask
  if instance.dynamic.mapZero(address, rounded, readOnly): HostError.None else: HostError.OutOfRange

proc protectMemory*(instance: var Instance, address, length: uint32, readOnly: bool): HostError =
  ## Unlike mapping, protection admits unaligned ranges and updates all pages they touch.
  if not instance.module.dynamic: return HostError.DynamicRequired
  if length == 0: return HostError.None
  if address < 65536 or uint64(length) > 0x100000000'u64 - uint64(address):
    return HostError.OutOfRange
  if instance.dynamic.protect(address, length, readOnly): HostError.None else: HostError.OutOfRange
