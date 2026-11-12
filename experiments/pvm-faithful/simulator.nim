# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## In-progress translation of pinned common/simulator.rs, Full(L2Hit), B64 and no tracer.
## The 32-lane ROB, packed resource guards, dependency masks, retirement order and
## fast-forward rules follow the source. Lane operations are currently explicit Nimony
## arrays; native SIMD/code-generation parity is a separate required gate before timing.
## This module must not supply accepted benchmark ratios while that gate is incomplete.

import std/[assertions, bitops]
import ./decode

include ./simulator_tables

type
  InstCost = object
    ## Same latency/decode/resource domains as the source InstCost.
    latency: int8
    slots, alu, load, store, mul, divide: uint32
  Simulator* = object
    ## Mutable scheduling state contains a borrowed code view, never owning program bytes.
    code: openArray[byte]
    cycles, instructions, decodeSlots, resources, inFlight, head, tail: uint32
    finished: bool
    state, remaining: array[32, int8]
    required, writes: array[32, uint16]
    dependencies, dependedBy, instructionBySlot: array[32, uint32]
    slotByRegister: array[16, int8]

const
  guardMask = 0xa888'u32
  maximumResources = 0x5444'u32

proc packed(cost: InstCost): uint32 {.inline.} =
  ## Each resource field leaves one guard bit for simultaneous packed subtraction tests.
  assert cost.alu <= 4 and cost.load <= 4 and cost.store <= 4 and cost.mul <= 1 and cost.divide <= 1
  cost.alu or (cost.load shl 4) or (cost.store shl 8) or (cost.mul shl 12) or (cost.divide shl 14)

proc clear(sim: var Simulator) =
  ## Reset source block state while retaining the program byte borrow.
  sim.cycles = 0
  sim.instructions = 0
  sim.finished = false
  sim.inFlight = 0
  sim.decodeSlots = 4
  sim.resources = maximumResources or guardMask
  sim.head = 0
  sim.tail = 0
  sim.state = default(array[32, int8])
  sim.remaining = default(array[32, int8])
  sim.required = default(array[32, uint16])
  sim.dependencies = default(array[32, uint32])
  sim.dependedBy = default(array[32, uint32])
  sim.writes = default(array[32, uint16])
  for index in 0..<16: sim.slotByRegister[index] = -1

proc newSimulator*(code: openArray[byte]): Simulator =
  ## Caller retains code for this simulator's whole lifetime, as for the source borrowed slice.
  result = Simulator(code: code)
  result.clear()

proc laneMask(condition: bool): int8 {.inline.} =
  ## SIMD comparisons yield all-one or zero bytes, not scalar bit positions.
  -int8(ord(condition))

proc maskPrimitive(data: ptr int8): uint32 {.importc: "faithful_simulator_mask",
    header: "simulator_simd.h", noSideEffect.}
  ## The source vector-to-scalar primitive; the caller supplies exactly 32 readable bytes.

proc mostSignificantBits(lanes: array[32, int8]): uint32 {.inline.} =
  ## Match picosimd AVX2 movemask on x86 and its portable fallback on ARM.
  maskPrimitive(addr lanes[0])

proc stateMask(sim: Simulator, expected: int8): uint32 {.inline.} =
  ## Source equality creates a byte vector before the scalar movemask boundary.
  var equal = default(array[32, int8])
  for lane in 0..<32: equal[lane] = laneMask(sim.state[lane] == expected)
  mostSignificantBits(equal)

proc tick[Finished, Decoded: static[bool]](sim: var Simulator) {.inline.} =
  ## Translate source vector operations in order; arrays are the portable SIMD representation.
  let retirement = rotateRightBits(sim.stateMask(4), int(sim.head))
  let retireCount = uint32(trailingZeroBits(not retirement))
  if retireCount != 0:
    # Use the same precomputed 32-by-33 circular retirement mask as the source.
    let retired = retireMasks[int(sim.head)][int(retireCount)]
    for lane in 0..<32: sim.state[lane] = sim.state[lane] and not retired[lane]
    assert retireCount <= sim.inFlight
    sim.inFlight -= retireCount
    sim.head = (sim.head+retireCount) and 31
  var waiting = default(array[32, int8])
  var started = default(array[32, int8])
  for lane in 0..<32:
    waiting[lane] = laneMask(sim.state[lane] == 2) and laneMask(sim.dependencies[lane] == 0)
  for selection in 0..<5:
    # Keep eligibility in byte vectors until the source oldest-entry selection boundary.
    assert (sim.resources and guardMask) == guardMask
    var enough = default(array[32, int8])
    for lane in 0..<32:
      let remaining = uint16(sim.resources)-sim.required[lane]
      enough[lane] = laneMask((uint32(remaining) and guardMask) == guardMask) and waiting[lane]
    let ordered = rotateRightBits(mostSignificantBits(enough), int(sim.head))
    let position = uint32(trailingZeroBits(ordered))
    if position >= 32: break
    let slot = (position+sim.head) and 31
    sim.resources -= uint32(sim.required[int(slot)])
    let selected = slotMasks[int(slot)]
    for lane in 0..<32:
      started[lane] = started[lane] or selected[lane]
      waiting[lane] = waiting[lane] and not selected[lane]
  var executing = default(array[32, int8])
  for lane in 0..<32:
    sim.state[lane] += 1'i8 and started[lane]
    executing[lane] = laneMask(sim.state[lane] == 3)
  var cycleCount = 1'i8
  when not Decoded:
    if Finished or retireCount == 0:
      # Unsigned horizontal minimum sees inactive entries as 255.
      var minimum = 255'u8
      for lane in 0..<32:
        minimum = min(minimum, cast[uint8](sim.remaining[lane] or (executing[lane] xor -1'i8)))
      if cast[int8](minimum) > 0: cycleCount = cast[int8](minimum)
  var completed = default(array[32, int8])
  for lane in 0..<32:
    let elapsed = int16(cycleCount and executing[lane])
    sim.remaining[lane] = int8(max(-128'i16, int16(sim.remaining[lane])-elapsed))
    completed[lane] = laneMask(sim.remaining[lane] == 0) and executing[lane]
  let completedBits = mostSignificantBits(completed)
  if completedBits != 0:
    # Zero latency releases dependencies and resources; retirement waits one further cycle.
    for lane in 0..<32: sim.dependencies[lane] = sim.dependencies[lane] and not completedBits
    var releasedRegisters = 0'u16
    for lane in 0..<32:
      let mask = cast[uint16](int16(completed[lane]))
      releasedRegisters = releasedRegisters or (sim.writes[lane] and mask)
      sim.writes[lane] = sim.writes[lane] and not mask
    for reg in 0..<16:
      sim.slotByRegister[reg] = sim.slotByRegister[reg] or laneMask((releasedRegisters and (
          1'u16 shl reg)) != 0)
    var releasedResources = 0'u16
    for lane in 0..<32:
      let mask = cast[uint16](int16(completed[lane]))
      releasedResources += sim.required[lane] and mask
      sim.required[lane] = sim.required[lane] and not mask
    sim.resources += uint32(releasedResources)
  for lane in 0..<32:
    sim.state[lane] += 1'i8 and executing[lane] and laneMask(sim.remaining[lane] == -1)
  when Decoded:
    for lane in 0..<32: sim.state[lane] += 1'i8 and laneMask(sim.state[lane] == 1)
    sim.decodeSlots = 4
  else:
    # Source no-decoding specialization relies on the preceding decoded cycle.
    assert sim.stateMask(1) == 0 and sim.decodeSlots == 4
  sim.cycles += uint32(cycleCount)

proc tickLoop[Finished: static[bool]](sim: var Simulator) {.noinline.} =
  ## Source loop always executes the first decoded-pending cycle, even for an empty ROB.
  tick[Finished, true](sim)
  let target = if Finished: 0'u32 else: 31'u32
  while sim.inFlight > target: tick[Finished, false](sim)

proc ensureDecode(sim: var Simulator, slots: uint32) {.inline.} =
  ## At most one decode cycle is needed unless a full reorder buffer forces retirement.
  assert slots <= 4
  if sim.decodeSlots < slots or sim.inFlight == 32: tickLoop[false](sim)

proc finish(sim: var Simulator) {.inline.} =
  ## Complete the scheduling model before a block cost becomes observable.
  sim.finished = true
  tickLoop[true](sim)

proc dispatchImpl[Dst, Src1, Src2, Src3: static[bool]](sim: var Simulator,
    dst, source1, source2, source3: uint32, resources: uint32, latency: int8) {.noinline.} =
  ## Source monomorphized optional-register dispatch; each lane update keeps the original order.
  let slot = sim.tail
  sim.tail = (sim.tail+1) and 31
  let selected = slotMasks[int(slot)]
  for lane in 0..<32:
    sim.remaining[lane] = (sim.remaining[lane] and not selected[lane]) or (latency and selected[lane])
  sim.required[int(slot)] = uint16(resources)
  var dependencies = 0'u32
  when Src1:
    let entry = sim.slotByRegister[register(source1)]
    if entry != -1: dependencies = dependencies or (1'u32 shl uint8(entry))
  when Src2:
    let entry = sim.slotByRegister[register(source2)]
    if entry != -1: dependencies = dependencies or (1'u32 shl uint8(entry))
  when Src3:
    let entry = sim.slotByRegister[register(source3)]
    if entry != -1: dependencies = dependencies or (1'u32 shl uint8(entry))
  when Src1 or Src2 or Src3: sim.dependencies[int(slot)] = dependencies
  when Dst:
    let reg = register(dst)
    let bits = registerMasks[reg]
    for lane in 0..<32:
      let mask = cast[uint16](int16(selected[lane]))
      sim.writes[lane] = (sim.writes[lane] and not bits[lane]) or (mask and bits[lane])
    sim.slotByRegister[reg] = int8(slot)
  for lane in 0..<32: sim.state[lane] += 1'i8 and selected[lane]
  sim.inFlight += 1
  sim.instructions += 1

proc dispatch[Dst, Src1, Src2, Src3: static[bool]](sim: var Simulator,
    dst, source1, source2, source3: uint32, cost: InstCost) {.inline.} =
  ## Preserve source decode-slot admission before publishing a new in-flight instruction.
  assert cost.latency >= 0
  sim.ensureDecode(cost.slots)
  dispatchImpl[Dst, Src1, Src2, Src3](sim, dst, source1, source2, source3, packed(cost), cost.latency)
  sim.decodeSlots -= cost.slots

proc moveRegister(sim: var Simulator, destination, source: uint32) =
  ## Source register renaming consumes a decode slot but does not allocate a ROB entry.
  let dst = register(destination)
  let src = register(source)
  sim.ensureDecode(1)
  let oldSlot = sim.slotByRegister[dst]
  if oldSlot != -1: sim.writes[int(oldSlot)] = sim.writes[int(oldSlot)] and not (1'u16 shl dst)
  let newSlot = sim.slotByRegister[src]
  if newSlot != -1: sim.writes[int(newSlot)] = sim.writes[int(newSlot)] or (1'u16 shl dst)
  sim.slotByRegister[dst] = newSlot
  sim.decodeSlots -= 1
  sim.instructions += 1

proc branchCost(sim: Simulator, offset, length, target: uint32): int8 =
  ## Default source heuristic recognizes trap/unlikely at either successor, or an absent successor.
  let following = uint64(offset)+uint64(length)
  if following >= uint64(sim.code.len): return 1
  let first = sim.code[int(following)]
  if first == 0 or first == 2: return 1
  if uint64(target) >= uint64(sim.code.len): return 1
  let second = sim.code[int(target)]
  if second == 0 or second == 2: 1'i8 else: 20'i8

proc takeBlockCost*(sim: var Simulator, cost: var uint32): bool =
  ## Source subtracts three slack cycles, clamps to one, and resets only a completed block.
  if sim.inFlight != 0 or not sim.finished: return false
  let cycles = sim.cycles
  sim.clear()
  cost = uint32(max(1'i32, cast[int32](cycles)-3))
  true

proc different2(a, b: uint32): uint32 {.inline.} =
  ## Source decode cost depends on normalized destination/source register equality.
  uint32(ord(register(a) != register(b)))

proc different3(a, b, c: uint32): uint32 {.inline.} =
  ## Two-address lowering needs another slot only when neither source equals the destination.
  uint32(ord(register(a) != register(b) and register(a) != register(c)))

proc emit2(sim: var Simulator, a, b: uint32, cost: InstCost) {.inline.} =
  ## Source dispatch_2op specialization.
  dispatch[true, true, false, false](sim, a, b, 0, 0, cost)

proc emit3(sim: var Simulator, a, b, c: uint32, cost: InstCost) {.inline.} =
  ## Source dispatch_3op specialization.
  dispatch[true, true, true, false](sim, a, b, c, 0, cost)

proc finishCost(sim: var Simulator, latency: int8) {.inline.} =
  ## Source dispatch_finish uses no resource or register dependency.
  dispatch[false, false, false, false](sim, 0, 0, 0, 0, InstCost(latency: latency, slots: 1))
  sim.finish()

proc visit*(sim: var Simulator, parsed: ParsedInstruction) =
  ## Exhaustive JamV1 source ParsingVisitor mapping for B64 and Full(L2Hit).
  let inst = parsed.instruction
  let a = inst.a
  let b = inst.b
  let c = inst.c
  case inst.opcode
  of Opcode.op_xor, Opcode.op_and, Opcode.op_or, Opcode.op_add_64, Opcode.op_sub_64:
    sim.emit3(a, b, c, InstCost(latency: 1, slots: 1+different3(a, b, c), alu: 1))
  of Opcode.op_add_32, Opcode.op_sub_32:
    sim.emit3(a, b, c, InstCost(latency: 2, slots: 2+different3(a, b, c), alu: 1))
  of Opcode.op_xor_imm, Opcode.op_and_imm, Opcode.op_or_imm, Opcode.op_add_imm_64,
      Opcode.op_shift_logical_right_imm_64, Opcode.op_shift_arithmetic_right_imm_64,
      Opcode.op_shift_logical_left_imm_64, Opcode.op_rotate_right_imm_64, Opcode.op_reverse_byte:
    sim.emit2(a, b, InstCost(latency: 1, slots: 1+different2(a, b), alu: 1))
  of Opcode.op_add_imm_32, Opcode.op_shift_logical_right_imm_32,
      Opcode.op_shift_arithmetic_right_imm_32, Opcode.op_shift_logical_left_imm_32,
      Opcode.op_rotate_right_imm_32:
    sim.emit2(a, b, InstCost(latency: 2, slots: 2+different2(a, b), alu: 1))
  of Opcode.op_count_leading_zero_bits_32, Opcode.op_count_leading_zero_bits_64,
      Opcode.op_count_set_bits_32, Opcode.op_count_set_bits_64, Opcode.op_sign_extend_8,
      Opcode.op_sign_extend_16, Opcode.op_zero_extend_16:
    sim.emit2(a, b, InstCost(latency: 1, slots: 1, alu: 1))
  of Opcode.op_count_trailing_zero_bits_32, Opcode.op_count_trailing_zero_bits_64:
    sim.emit2(a, b, InstCost(latency: 2, slots: 1, alu: 2))
  of Opcode.op_shift_logical_right_64, Opcode.op_shift_arithmetic_right_64,
      Opcode.op_shift_logical_left_64, Opcode.op_rotate_left_64, Opcode.op_rotate_right_64:
    sim.emit3(a, b, c, InstCost(latency: 1, slots: 2+different2(a, b), alu: 1))
  of Opcode.op_shift_logical_right_32, Opcode.op_shift_arithmetic_right_32,
      Opcode.op_shift_logical_left_32, Opcode.op_rotate_left_32, Opcode.op_rotate_right_32:
    sim.emit3(a, b, c, InstCost(latency: 2, slots: 3+different2(a, b), alu: 1))
  of Opcode.op_shift_logical_right_imm_alt_64, Opcode.op_shift_arithmetic_right_imm_alt_64,
      Opcode.op_shift_logical_left_imm_alt_64, Opcode.op_rotate_right_imm_alt_64:
    sim.emit2(a, b, InstCost(latency: 1, slots: 3, alu: 1))
  of Opcode.op_shift_logical_right_imm_alt_32, Opcode.op_shift_arithmetic_right_imm_alt_32,
      Opcode.op_shift_logical_left_imm_alt_32, Opcode.op_rotate_right_imm_alt_32:
    sim.emit2(a, b, InstCost(latency: 2, slots: 4, alu: 1))
  of Opcode.op_set_less_than_unsigned, Opcode.op_set_less_than_signed:
    sim.emit3(a, b, c, InstCost(latency: 3, slots: 3, alu: 1))
  of Opcode.op_set_less_than_unsigned_imm, Opcode.op_set_less_than_signed_imm,
      Opcode.op_set_greater_than_unsigned_imm, Opcode.op_set_greater_than_signed_imm:
    sim.emit2(a, b, InstCost(latency: 3, slots: 3, alu: 1))
  of Opcode.op_cmov_if_zero, Opcode.op_cmov_if_not_zero:
    dispatch[true, true, true, true](sim, a, a, b, c, InstCost(latency: 2, slots: 2, alu: 1))
  of Opcode.op_cmov_if_zero_imm, Opcode.op_cmov_if_not_zero_imm:
    sim.emit3(a, a, b, InstCost(latency: 2, slots: 3, alu: 1))
  of Opcode.op_maximum, Opcode.op_maximum_unsigned, Opcode.op_minimum, Opcode.op_minimum_unsigned:
    sim.emit3(a, b, c, InstCost(latency: 3, slots: 2+different3(a, b, c), alu: 1))
  of Opcode.op_load_indirect_u8, Opcode.op_load_indirect_i8, Opcode.op_load_indirect_u16,
      Opcode.op_load_indirect_i16, Opcode.op_load_indirect_u32, Opcode.op_load_indirect_i32,
      Opcode.op_load_indirect_u64:
    sim.emit2(a, b, InstCost(latency: 25, slots: 1, alu: 1, load: 1))
  of Opcode.op_load_u8, Opcode.op_load_i8, Opcode.op_load_u16, Opcode.op_load_i16,
      Opcode.op_load_u32, Opcode.op_load_i32, Opcode.op_load_u64:
    dispatch[true, false, false, false](sim, a, 0, 0, 0, InstCost(latency: 25, slots: 1, alu: 1, load: 1))
  of Opcode.op_store_imm_indirect_u8, Opcode.op_store_imm_indirect_u16,
      Opcode.op_store_imm_indirect_u32, Opcode.op_store_imm_indirect_u64,
      Opcode.op_store_u8, Opcode.op_store_u16, Opcode.op_store_u32, Opcode.op_store_u64:
    dispatch[false, true, false, false](sim, 0, a, 0, 0, InstCost(latency: 25, slots: 1, alu: 1, store: 1))
  of Opcode.op_store_indirect_u8, Opcode.op_store_indirect_u16,
      Opcode.op_store_indirect_u32, Opcode.op_store_indirect_u64:
    dispatch[false, true, true, false](sim, 0, a, b, 0, InstCost(latency: 25, slots: 1, alu: 1, store: 1))
  of Opcode.op_store_imm_u8, Opcode.op_store_imm_u16, Opcode.op_store_imm_u32,
      Opcode.op_store_imm_u64:
    dispatch[false, false, false, false](sim, 0, 0, 0, 0, InstCost(latency: 25, slots: 1, alu: 1, store: 1))
  of Opcode.op_branch_less_unsigned, Opcode.op_branch_less_signed,
      Opcode.op_branch_greater_or_equal_unsigned, Opcode.op_branch_greater_or_equal_signed,
      Opcode.op_branch_eq, Opcode.op_branch_not_eq:
    let length = if parsed.nextOffset >= parsed.offset: parsed.nextOffset-parsed.offset else: 0'u32
    let latency = sim.branchCost(parsed.offset, length, inst.x)
    dispatch[false, true, true, false](sim, 0, a, b, 0, InstCost(latency: latency, slots: 1, alu: 1))
    sim.finish()
  of Opcode.op_branch_eq_imm, Opcode.op_branch_not_eq_imm, Opcode.op_branch_less_unsigned_imm,
      Opcode.op_branch_less_signed_imm, Opcode.op_branch_greater_or_equal_unsigned_imm,
      Opcode.op_branch_greater_or_equal_signed_imm, Opcode.op_branch_less_or_equal_unsigned_imm,
      Opcode.op_branch_less_or_equal_signed_imm, Opcode.op_branch_greater_unsigned_imm,
      Opcode.op_branch_greater_signed_imm:
    let length = if parsed.nextOffset >= parsed.offset: parsed.nextOffset-parsed.offset else: 0'u32
    let latency = sim.branchCost(parsed.offset, length, inst.y)
    dispatch[false, true, false, false](sim, 0, a, 0, 0, InstCost(latency: latency, slots: 1, alu: 1))
    sim.finish()
  of Opcode.op_div_unsigned_32, Opcode.op_div_signed_32, Opcode.op_rem_unsigned_32,
      Opcode.op_rem_signed_32, Opcode.op_div_unsigned_64, Opcode.op_div_signed_64,
      Opcode.op_rem_unsigned_64, Opcode.op_rem_signed_64:
    sim.emit3(a, b, c, InstCost(latency: 60, slots: 4, alu: 1, divide: 1))
  of Opcode.op_and_inverted, Opcode.op_or_inverted:
    sim.emit3(a, b, c, InstCost(latency: 2, slots: 3, alu: 1))
  of Opcode.op_xnor:
    sim.emit3(a, b, c, InstCost(latency: 2, slots: 2+different3(a, b, c), alu: 1))
  of Opcode.op_negate_and_add_imm_64:
    sim.emit2(a, b, InstCost(latency: 2, slots: 3, alu: 1))
  of Opcode.op_negate_and_add_imm_32:
    sim.emit2(a, b, InstCost(latency: 3, slots: 4, alu: 1))
  of Opcode.op_move_reg:
    sim.moveRegister(a, b)
  of Opcode.op_load_imm:
    dispatch[true, false, false, false](sim, a, 0, 0, 0, InstCost(latency: 1, slots: 1))
  of Opcode.op_load_imm64:
    dispatch[true, false, false, false](sim, a, 0, 0, 0, InstCost(latency: 1, slots: 2))
  of Opcode.op_mul_32:
    sim.emit3(a, b, c, InstCost(latency: 4, slots: 2+different3(a, b, c), alu: 1, mul: 1))
  of Opcode.op_mul_64:
    sim.emit3(a, b, c, InstCost(latency: 3, slots: 1+different3(a, b, c), alu: 1, mul: 1))
  of Opcode.op_mul_imm_32:
    sim.emit2(a, b, InstCost(latency: 4, slots: 2+different2(a, b), alu: 1, mul: 1))
  of Opcode.op_mul_imm_64:
    sim.emit2(a, b, InstCost(latency: 3, slots: 1+different2(a, b), alu: 1, mul: 1))
  of Opcode.op_mul_upper_signed_signed, Opcode.op_mul_upper_unsigned_unsigned:
    sim.emit3(a, b, c, InstCost(latency: 4, slots: 4, alu: 1, mul: 1))
  of Opcode.op_mul_upper_signed_unsigned:
    sim.emit3(a, b, c, InstCost(latency: 6, slots: 4, alu: 1, mul: 1))
  of Opcode.op_invalid, Opcode.op_trap, Opcode.op_fallthrough:
    sim.finishCost(2)
  of Opcode.op_jump, Opcode.op_load_imm_and_jump:
    sim.finishCost(15)
  of Opcode.op_jump_indirect:
    dispatch[false, true, false, false](sim, 0, a, 0, 0, InstCost(latency: 22, slots: 1))
    sim.finish()
  of Opcode.op_load_imm_and_jump_indirect:
    dispatch[false, true, false, false](sim, 0, b, 0, 0, InstCost(latency: 22, slots: 1))
    sim.finish()
  of Opcode.op_unlikely:
    dispatch[false, false, false, false](sim, 0, 0, 0, 0, InstCost(latency: 40, slots: 1))
  of Opcode.op_ecalli:
    dispatch[false, false, false, false](sim, 0, 0, 0, 0, InstCost(latency: 100, slots: 4, alu: 1))

proc atBlockStart*(sim: Simulator): bool =
  ## Match GasVisitorT::is_at_start_of_basic_block without publishing scheduler internals.
  sim.instructions == 0
