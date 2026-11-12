# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-block pipeline simulation with approved PolkaVM wrapped-target pricing; see spec/pvm-gas.md.
## Exposes blockGas, nominal BlockGas/GasCycleLimit values and guarded GasResult outcomes.
## The simulator borrows an immutable program and uses bounded stack storage only.

import ../program

type
  BlockGas* = distinct uint64 ## A computed block charge is distinct from both a program address and a local work limit.
  GasCycleLimit* = distinct uint64 ## Local simulation ceiling counts pipeline cycles, including the three-cycle adjustment.
  GasError* {.pure.} = enum ## Local failures never masquerade as guest out-of-gas or publish partial costs.
    Uninitialized, None, InvalidStart, CycleLimitExceeded, NegativeBranchTarget
  GasResult* = object ## Only a completed simulation carries a charge; private fields prevent success forgery.
    case status: GasError
    of None:
      # Copied scalar result has no lifetime dependency on the borrowed program.
      completed: BlockGas
    else:
      # Failures contain no cost or partial pipeline progress.
      discard
  # ALU/load/store occupancy never exceeds4, multiply/divide never exceeds1; signed bytes retain exact nonnegative counters.
  Units = array[5, int8]
  # Register sets are thirteen-bit masks; all indices come from the validated decoder.
  Profile = object
    sources, destinations: uint16
    cycles: int8 # The exhaustive profile table grants0..100 cycles; execution only decrements positive latency.
    slots: int
    units: Units
  # Retired entries are removed only from the prefix after a simultaneous cycle transition.
  Stage {.pure.} = enum
    Decoding, Waiting, Executing, Executed
  # At most 32 active entries; dependency bits refer to positions in this compact buffer.
  Entry = object
    stage: Stage
    left: int8 # Copied profile latency stays within0..100 throughout execution.
    dependencies: uint32
    clobbers: uint16
    units: Units

func error*(r: GasResult): GasError =
  ## Read status without exposing the variant tag to mutation.
  r.status

func value*(r: GasResult): BlockGas {.requires: r.status == GasError.None.} =
  ## The caller must select success before extracting the copied block charge.
  r.completed

func bit(index: RegisterIndex): uint16 =
  ## Convert an already saturated register identifier to its singleton dependency set.
  1'u16 shl int(byte(index))

func profile(item: Instruction): Profile =
  ## Derive all syntactically read/written registers, including conditional-move fallbacks.
  result = Profile(sources: 0, destinations: 0, cycles: 1, slots: 1,
    units: [1'i8, 0'i8, 0'i8, 0'i8, 0'i8])
  let a = bit(item.a)
  let b = bit(item.b)
  let d = bit(item.d)
  # Register roles follow the instruction mutations, not operand field names alone.
  case item.opcode
  of 20, 51..58, 80:
    # Immediate/direct loads and static load-jump only write A.
    result.destinations = a
  of 50, 59..62, 70..73, 81..90:
    # Stores, indirect jump and immediate branches read A without a register write.
    result.sources = a
  of 100..110:
    # Unary and move operations read A and write D.
    result.sources = a
    result.destinations = d
  of 120..123, 170..175:
    # Indirect stores and register branches read both decoded registers.
    result.sources = a or b
  of 124..161, 180:
    # Indirect loads, immediate arithmetic and indirect load-jump read B and write A.
    result.sources = b
    result.destinations = a
    if item.opcode in {147'u8, 148'u8}:
      # The unselected conditional assignment retains the old destination value.
      result.sources = result.sources or a
  of 190..230:
    # Binary arithmetic reads A/B and writes D, including the conditional fallback.
    result.sources = a or b
    result.destinations = d
    if item.opcode in {218'u8, 219'u8}: result.sources = result.sources or d
  else:
    # Trap, fallthrough, unlikely, host calls, immediate stores and static jump read no registers.
    discard
  let overlap = (result.sources and result.destinations) != 0
  let shiftOverlap = byte(item.a) == byte(item.d)
  # The exhaustive table retains separate latency, frontend demand and execution resources.
  case item.opcode
  of 0, 1:
    # Finishing instructions consume no execution units.
    result.cycles = 2
    result.units[0] = 0
  of 2:
    # An unlikely marker is a long pipeline operation, not a block terminator.
    result.cycles = 40
    result.units[0] = 0
  of 10:
    # A host call has fixed cost and continues the same gas block.
    result.cycles = 100
    result.slots = 4
  of 20, 51:
    # Immediate loads consume frontend slots but no execution unit.
    result.slots = (if item.opcode == 20: 2 else: 1)
    result.units[0] = 0
  of 30..33, 59..62, 70..73, 120..123:
    # Every store uses one ALU and one store unit for 25 cycles.
    result.cycles = 25
    result.units[2] = 1
  of 52..58, 124..130:
    # Every load uses one ALU and one load unit for 25 cycles.
    result.cycles = 25
    result.units[1] = 1
  of 40, 80:
    # Static jumps have fixed latency and no execution resource demand.
    result.cycles = 15
    result.units[0] = 0
  of 50, 180:
    # Indirect jumps still wait for their register dependencies.
    result.cycles = 22
    result.units[0] = 0
  of 81..90, 170..175:
    # The caller fills the branch latency using actual raw target bytes.
    result.cycles = 20
  of 100:
    # Move elimination is handled in the frontend without entering the reorder buffer.
    result.cycles = 0
    result.units[0] = 0
  of 101..104, 107..109:
    # Counts/extensions use one ALU cycle independently of aliasing.
    discard
  of 105, 106:
    # Trailing-zero counts occupy two ALUs for two cycles.
    result.cycles = 2
    result.units[0] = 2
  of 110, 132..134, 149, 151..153, 158, 200, 201, 210..212:
    # Simple full-width operations save one decode slot when a source is overwritten.
    result.slots = (if overlap: 1 else: 2)
  of 131, 138..140, 160, 190, 191, 226:
    # Word arithmetic and XNOR use two cycles and overlap-sensitive decode demand.
    result.cycles = 2
    result.slots = (if overlap: 2 else: 3)
  of 135, 192:
    # Word multiplication occupies the unique multiply unit for four cycles.
    result.cycles = 4
    result.slots = (if overlap: 2 else: 3)
    result.units[3] = 1
  of 150, 202:
    # Full-width multiplication has three-cycle latency.
    result.cycles = 3
    result.slots = (if overlap: 1 else: 2)
    result.units[3] = 1
  of 136, 137, 142, 143, 216, 217:
    # Comparisons have fixed three-cycle and three-slot costs.
    result.cycles = 3
    result.slots = 3
  of 141:
    # Word negated addition needs four decode slots and three cycles.
    result.cycles = 3
    result.slots = 4
  of 144..146, 161:
    # Alternate word shifts have immediate values and register shift amounts.
    result.cycles = 2
    result.slots = 4
  of 147, 148:
    # Immediate conditional moves consume three slots, including the retained destination.
    result.cycles = 2
    result.slots = 3
  of 154, 224, 225:
    # Negated addition and inverted logical operations have fixed two-cycle latency.
    result.cycles = 2
    result.slots = 3
  of 155..157, 159:
    # Alternate full-width shifts have fixed decode demand.
    result.slots = 3
  of 193..196, 203..206:
    # Division and remainder occupy the unique divide unit for sixty cycles.
    result.cycles = 60
    result.slots = 4
    result.units[4] = 1
  of 197..199, 221, 223:
    # Only the value source A, not the shift-count source B, affects this discount.
    result.cycles = 2
    result.slots = (if shiftOverlap: 3 else: 4)
  of 207..209, 220, 222:
    # Full-width variable shifts use the same A/D overlap predicate.
    result.slots = (if shiftOverlap: 2 else: 3)
  of 213..215:
    # Mixed-sign high multiplication has two additional cycles.
    result.cycles = (if item.opcode == 215: 6 else: 4)
    result.slots = 4
    result.units[3] = 1
  of 218, 219:
    # Register conditional moves have two slots and two cycles.
    result.cycles = 2
    result.slots = 2
  of 227..230:
    # Min/max overlap changes decode demand but not latency.
    result.cycles = 3
    result.slots = (if overlap: 2 else: 3)
  else:
    # Validated instructions exhaust the pinned opcode table.
    discard

func fits(needed, available: Units): bool =
  ## Check memberwise resource availability without signed subtraction underflow.
  result = true
  # Every resource kind must be simultaneously available.
  for i in 0..<5:
    if needed[i] > available[i]: return false

func lowestEntryIndex(mask: uint32): cint {.importc: "__builtin_ctz", nodecl.}
  ## Count trailing zeros of a nonzero mask on the supported C toolchain.

proc blockGas*(program: Program, start: CodeAddress, limit: GasCycleLimit): GasResult =
  ## Compute the whole block charge, with no register/memory/gas mutation or retained allocation.
  ## start must be a block boundary; the cycle ceiling is local work policy, not guest gas.
  ## A pending copied decode survives slot stalls; no extra cycle or owner-bound cache is introduced.
  let boundary = basicBlockStart(program, start)
  # Reject default owners, operand bytes and interior instruction addresses uniformly.
  if boundary.error != ProgramError.None or not boundary.value:
    return GasResult(status: GasError.InvalidStart)
  var rob = default(array[32, Entry])
  var count = 0
  var busy = 0'u32 # A bit is set exactly while that active entry has nonzero remaining latency.
  var waiting = 0'u32 # Bits mark exactly the active entries in Stage.Waiting.
  var transitioning = 0'u32 # Bits mark exactly the active Decoding and Executing entries.
  var pc = uint64(start)
  # A stalled decode keeps one copied instruction/profile until admission advances the PC.
  var pending = false
  var item = default(Instruction)
  var cost = default(Profile)
  var ended = false
  var cycles = 0'u64
  var slots = 4
  var starts = 5
  var available: Units = [4'i8, 4'i8, 4'i8, 1'i8, 1'i8]
  # Each transition decodes a bounded instruction, starts one entry, or advances a bounded cycle.
  while true:
    if not ended and count < 32:
      if not pending:
        # A validated block ends in T. Slot stalls must not decode/profile this same PC again.
        let decoded = instruction(program, CodeAddress(pc))
        if decoded.error != ProgramError.None: return GasResult(status: GasError.InvalidStart)
        item = decoded.value
        cost = profile(item)
        pending = true
      if cost.slots <= slots:
        # Branch cost inspects raw bytes even when the target is not a valid jump destination.
        if item.opcode in {81'u8..90'u8, 170'u8..175'u8}:
          # PolkaVM decodes static offsets with u32 wrapping before raw target-byte pricing.
          # Both operands fit32 bits, so the sum fits33 bits; the negative magnitude is bounded by2^31.
          let offset = if item.displacement < 0: 0x100000000'u64 - uint64(-item.displacement)
            else: uint64(item.displacement)
          let target = ((pc and 0xffffffff'u64) + offset) and 0xffffffff'u64
          let following = instructionByte(program, CodeAddress(pc + 1 + uint64(item.skip)))
          let taken = instructionByte(program, CodeAddress(target))
          if following.value in {0'u8, 2'u8} or taken.value in {0'u8, 2'u8}:
            # Either trap/unlikely successor reduces branch latency, independent of branch outcome.
            cost.cycles = 1
        slots -= cost.slots
        if item.opcode == 100:
          # Rename every outstanding producer; a ready source removes the destination's old producer.
          for i in 0..<count:
            if (rob[i].clobbers and cost.sources) != 0:
              rob[i].clobbers = rob[i].clobbers or cost.destinations
            else:
              # Unrelated producers no longer own the moved-to register.
              rob[i].clobbers = rob[i].clobbers and not cost.destinations
        else:
          # Capture read-after-write dependencies before replacing the destination producer.
          var deps = 0'u32
          for i in 0..<count:
            if (rob[i].clobbers and cost.sources) != 0: deps = deps or (1'u32 shl i)
            rob[i].clobbers = rob[i].clobbers and not cost.destinations
          rob[count] = Entry(stage: Stage.Decoding, left: cost.cycles,
            dependencies: deps, clobbers: cost.destinations, units: cost.units)
          if cost.cycles != 0: busy = busy or (1'u32 shl count) # The enclosing count<32 guard proves this shift.
          transitioning = transitioning or (1'u32 shl count)
          inc count
        ended = terminatesBlock(item.opcode)
        pc += 1 + uint64(item.skip)
        pending = false # Only successful pipeline admission consumes this decoded instruction.
        continue
    if starts > 0:
      # Pick the oldest waiting entry whose dependencies have finished and resources fit.
      var selected = -1
      var candidates = waiting
      while candidates != 0:
        # The lowest bit is the oldest remaining candidate and is in the active prefix.
        let i = int(lowestEntryIndex(candidates))
        if fits(rob[i].units, available):
          if (rob[i].dependencies and busy) == 0:
            # One bounded mask intersection replaces rescanning every retained dependency on each issue attempt.
            selected = i
            break
        candidates = candidates and (candidates - 1'u32)
      if selected >= 0:
        # Resource occupancy persists until the last executing cycle, not merely this issue slot.
        for i in 0..<5: available[i] -= rob[selected].units[i]
        rob[selected].stage = Stage.Executing
        let bit = 1'u32 shl selected
        waiting = waiting and not bit
        transitioning = transitioning or bit
        dec starts
        continue
    if ended and count == 0:
      # The normative pipeline startup adjustment saturates at a minimum charge of one.
      return GasResult(status: GasError.None,
        completed: BlockGas(if cycles > 3: cycles - 3 else: 1))
    if cycles == uint64(limit):
      # Check before increment so even the maximum uint64 work limit cannot wrap.
      return GasResult(status: GasError.CycleLimitExceeded)
    inc cycles
    slots = 4
    starts = 5
    # Only entries already Executed before this cycle can retire.
    let unexecuted = waiting or transitioning
    let retired = if unexecuted == 0: count else: int(lowestEntryIndex(unexecuted))
    var transitions = transitioning
    while transitions != 0:
      # Process the old Decoding and Executing entries in buffer order.
      let i = int(lowestEntryIndex(transitions))
      let bit = 1'u32 shl i
      transitions = transitions and (transitions - 1'u32)
      if rob[i].stage == Stage.Decoding:
        rob[i].stage = Stage.Waiting
        waiting = waiting or bit
        transitioning = transitioning and not bit
      else:
        # Executing entries stay in the mask through their zero-latency cycle.
        if rob[i].left == 1:
          # Release resources on the transition to zero remaining latency.
          for j in 0..<5: available[j] += rob[i].units[j]
          busy = busy and not bit # Readiness changes at the same one-to-zero latency transition, before the next issue cycle.
        if rob[i].left > 0:
          dec rob[i].left
        else:
          # Zero remaining latency becomes executed only on the following cycle.
          rob[i].stage = Stage.Executed
          transitioning = transitioning and not bit
    if retired > 0:
      # Removed dependencies already have zero latency; reindex the remaining dependency bits.
      for i in retired..<count:
        rob[i - retired] = rob[i]
        rob[i - retired].dependencies = rob[i].dependencies shr retired
      if retired == 32:
        # A complete buffer retirement must never shift by the word width.
        busy = 0
        waiting = 0
        transitioning = 0
      else:
        # Active entry indices move by the same retired prefix as their dependency masks.
        busy = busy shr retired
        waiting = waiting shr retired
        transitioning = transitioning shr retired
      count -= retired
