# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 refinement hosts 9..14 own immutable inner-machine lifecycle, memory and bounded raw invocation.
## Exposes bounded capture, copied inspection and atomic lifecycle/page/transfer/invocation transitions.

import ./[machine, program, step, gas]

type
  InnerMachineId* = distinct uint64 ## Full guest register domain; identifiers outside 0..62 are absent.
  InnerMachineLimit* = distinct uint32 ## Local slot ceiling, independent of the protocol's 63-machine limit.
  InnerProgramLimit* = distinct uint64 ## Total retained program bytes, independent of each program's parsing budget.
  InnerMachineLimits* = object ## Immutable policy applies to every successor of one invocation-local map.
    items*: InnerMachineLimit
    program*: ProgramByteLimit
    total*: InnerProgramLimit
    jumps*: JumpCountLimit
    pages*: PageLimit
    steps*: ExecutionStepLimit ## Independent per-segment instruction policy; outer host-count policy bounds segment count.
    cycles*: GasCycleLimit ## Per-block gas-analysis policy for the raw inner execution engine.
  InnerMachineError* {.pure.} = enum ## Local/default refusals expose no response or partially modified map.
    Uninitialized, None, InvalidContext, InvalidMemory, LimitExceeded, Missing, ExecutionFailure
  InnerMachineInfo* = object ## Copied metadata and immutable child owners cannot rewrite the original map.
    program*: Program
    memory*: Memory
    pc*: CodeAddress
    blockCharged*: bool
  InnerData = ref object ## One immutable program/memory pair has no back-reference to its map.
    info: InnerMachineInfo
    size: uint64
    id: uint64
  MapData = ref object ## Sorted immutable slots are bounded by 63, independently of full-width guest IDs.
    slots: seq[InnerData]
    bytes: uint64
    limits: InnerMachineLimits
  InnerMachines* = object ## Default is invalid; explicit capture creates the valid empty map.
    data: nil MapData
  InnerMachineTransition* = object ## A charged host response and its exact immutable map successor travel together.
    response*: HostResponse
    machines*: InnerMachines
  InnerMachineResult*[T] = object ## Private tags and payloads require success before extraction.
    case status: InnerMachineError
    of None:
      completed: T
    of ExecutionFailure:
      reason: StepError
    else:
      discard                     # Local failures retain neither scratch bytes nor a manufactured protocol result.

func error*[T](outcome: InnerMachineResult[T]): InnerMachineError =
  ## Inspect the reason without writable tag access.
  outcome.status
func value*[T](outcome: InnerMachineResult[T]): T
    {.requires: outcome.status == InnerMachineError.None.} =
  ## Extract only complete successful owners or transitions, including protocol-error responses.
  outcome.completed
func executionError*[T](outcome: InnerMachineResult[T]): StepError
    {.requires: outcome.status == InnerMachineError.ExecutionFailure.} =
  ## Extract only a nested engine's exact local refusal, without fabricated frame or map progress.
  outcome.reason
proc captureInnerMachines*(limits: InnerMachineLimits): InnerMachines =
  ## Capture finite caller policies beside an explicitly empty map, with no guest slots implicitly present.
  InnerMachines(data: MapData(slots: @[], bytes: 0, limits: limits))
proc innerMachineCount*(machines: InnerMachines): InnerMachineResult[uint32] =
  ## Copy the actual map cardinality; missing owners cannot masquerade as empty.
  let data = machines.data
  if data == nil: return InnerMachineResult[uint32](status: InnerMachineError.InvalidContext)
  InnerMachineResult[uint32](status: InnerMachineError.None, completed: uint32(data.slots.len))
proc innerMachine*(machines: InnerMachines, id: InnerMachineId): InnerMachineResult[
    InnerMachineInfo] =
  ## Inspect a full-width guest identifier without narrowing before the protocol-domain check.
  let data = machines.data
  if data == nil: return InnerMachineResult[InnerMachineInfo](
      status: InnerMachineError.InvalidContext)
  if uint64(id) >= 63: return InnerMachineResult[InnerMachineInfo](
      status: InnerMachineError.Missing)
  for slot in data.slots:
    if slot.id == uint64(id):
      return InnerMachineResult[InnerMachineInfo](status: InnerMachineError.None,
          completed: slot.info) # Sorted slots retain exact identity.
  InnerMachineResult[InnerMachineInfo](status: InnerMachineError.Missing)

func charged(gas: MachineGas, cost: uint64, registers: RegisterFile, memory: Memory): HostResponse =
  ## Costs are below 2^61+1863, so exact deficits always fit the canonical signed-gas magnitude.
  let credit = uint64(gas)
  if credit < cost:
    return HostResponse(action: HostAction.OutOfGas, gas: MachineGas(0),
      gasDeficit: GasDeficit(cost-credit), registers: registers,
          memory: memory) # No register/map mutation on OOG.
  HostResponse(action: HostAction.Continue, gas: MachineGas(credit-cost),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)

proc createInnerMachine*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Evaluate Omega_M atomically, copying a validated deblob from the caller's stable immutable memory.
  template fail(reason: InnerMachineError) =
    return InnerMachineResult[InnerMachineTransition](status: reason)
  let data = machines.data
  if data == nil: fail(InnerMachineError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None: fail(
      InnerMachineError.InvalidMemory)
  let size = uint64(registers[8])
  # Quotient/remainder avoids multiplying an untrusted 64-bit length by 112 before dividing.
  let cost = 1862'u64 + (size div 1024)*112 + ((size mod 1024)*112+1023) div 1024
  var transition = InnerMachineTransition(machines: machines,
    response: charged(gas, cost, registers, memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if transition.response.action == HostAction.OutOfGas: done() # Gas precedes all protocol row decisions.
  if data.slots.len >= 63:
    transition.response.registers[7] = RegisterValue(high(uint64)-4)
    done() # FULL precedes pointer readability, decoding and local capture policies.
  let limits = data.limits
  if uint64(data.slots.len) >= uint64(uint32(limits.items)) or size > uint64(limits.program) or
      data.bytes > uint64(limits.total) or size > uint64(limits.total)-data.bytes:
    fail(InnerMachineError.LimitExceeded) # Proven remaining budget precedes allocation and subtraction.
  let bytes = readBytes(memory, MemoryAddress(uint64(registers[7])), MemoryLength(size),
    MemoryByteLimit(uint64(limits.program)))
  case bytes.error
  of MachineError.None:
    discard # The complete copied natural range is available for exact deblob validation.
  of MachineError.Fault, MachineError.InvalidRange:
    transition.response.action = HostAction.Panic
    done() # Guest unreadability never creates a partial slot.
  of MachineError.LimitExceeded:
    fail(InnerMachineError.LimitExceeded)
  else:
    fail(InnerMachineError.InvalidMemory)
  let parsed = decodeJamProgram(bytes.value, CodeAddress(uint64(registers[9])), limits.program, limits.jumps)
  if parsed.error == ProgramError.LimitExceeded: fail(InnerMachineError.LimitExceeded)
  if parsed.error != ProgramError.None:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # HUH preserves the map for malformed programs or invalid entry PCs.
  var at = 0
  while at < data.slots.len and data.slots[at].id == uint64(
      at): inc at # First missing ordinal is the smallest free ID.
  let id = uint64(at)
  var slots = newSeqOfCap[InnerData](data.slots.len+1)
  for index in 0..<at: slots.add(data.slots[index]) # Share immutable prefix owners without sharing mutable sequence metadata.
  slots.add(InnerData(info: InnerMachineInfo(program: parsed.value,
    memory: captureMemory([], limits.pages).value, pc: CodeAddress(uint64(registers[9])),
    blockCharged: false), size: size, id: id))
  for index in at..<data.slots.len: slots.add(data.slots[
      index]) # Keep the ordered suffix beyond the inserted hole.
  transition.machines = InnerMachines(data: MapData(slots: slots,
    bytes: data.bytes+size, limits: limits)) # The local total preflight proved the sum cannot wrap.
  transition.response.registers[7] = RegisterValue(uint64(id))
  done()

proc expungeInnerMachine*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Evaluate Omega_X, returning the removed PC and freeing only that immutable slot's byte accounting.
  let data = machines.data
  if data == nil: return InnerMachineResult[InnerMachineTransition](
      status: InnerMachineError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None:
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.InvalidMemory)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  let credit = uint64(gas)
  if credit < 335:
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(335-credit)
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
      completed: transition) # Explicit response storage preserves memory ownership on every early exit.
  transition.response.gas = MachineGas(credit-335)
  # Affordable deletion changes only r7 and the exact immutable map successor.
  let id = uint64(registers[7])
  let found = machines.innerMachine(InnerMachineId(id))
  if found.error == InnerMachineError.Missing:
    transition.response.registers[7] = RegisterValue(high(uint64)-3) # WHO preserves all slots and bytes.
  else:
    var slots = newSeqOfCap[InnerData](data.slots.len-1)
    var removed = 0'u64
    for slot in data.slots:
      if slot.id == id:
        removed = slot.size # Successful lookup guarantees exactly one matching accounted row.
      else:
        slots.add(slot) # Share every immutable surviving slot in the original order.
    transition.machines = InnerMachines(data: MapData(slots: slots,
      bytes: data.bytes-removed, limits: data.limits)) # Only accounted retained bytes are subtracted.
    transition.response.registers[7] = RegisterValue(uint64(found.value.pc))
  InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None, completed: transition)

proc innerPagesResponse*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Apply Omega_Z with exact representable gas, ordered protocol checks and an atomic immutable RAM successor.
  template fail(reason: InnerMachineError) =
    return InnerMachineResult[InnerMachineTransition](status: reason)
  let data = machines.data
  if data == nil: fail(InnerMachineError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None: fail(
      InnerMachineError.InvalidMemory)
  let count = uint64(registers[9])
  let mode = uint64(registers[10])
  var base = 80'u64
  var linear = 0'u64
  case mode
  of 0:
    base = 212
    linear = 118 # Free/clear is priced even if no pages were previously present.
  of 1, 2:
    base = 275
    linear = 121 # Both zero-filled allocation modes share one price.
  of 3, 4:
    base = 130
    linear = 29 # Permission-only updates retain all existing byte values.
  else:
    discard # Invalid modes pay the constant invalid price, regardless of the count.
  if linear != 0 and count > (high(uint64)-base) div linear:
    fail(InnerMachineError.LimitExceeded) # The mathematical gas cost cannot be represented; never wrap before WHO/HUH.
  let cost = base+count*linear
  let credit = uint64(gas)
  if credit < cost and cost-credit > 0x8000000000000000'u64:
    fail(InnerMachineError.LimitExceeded) # The existing terminal gas representation cannot carry a larger negative magnitude.
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if credit < cost:
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(cost-credit)
    done() # Underfunding precedes every guest identity, geometry or permission test.
  transition.response.gas = MachineGas(credit-cost)
  let id = uint64(registers[7])
  let found = machines.innerMachine(InnerMachineId(id))
  if found.error == InnerMachineError.Missing:
    transition.response.registers[7] = RegisterValue(high(uint64)-3)
    done() # WHO precedes invalid mode, inaccessible pages and malformed page bounds.
  let first = uint64(registers[8])
  if mode > 4 or first < 16 or first >= 0x100000 or count >= 0x100000-first:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # Strict p+c<2^20 is proven without forming an untrusted sum.
  let past = first+count # Prior subtraction check proved this natural sum strictly below 2^20.
  let source = found.value
  if mode > 2:
    for ordinal in first..<past:
      if source.memory.pageImage(PageIndex(uint32(ordinal))).value.access ==
          PageAccess.Inaccessible:
        transition.response.registers[7] = RegisterValue(high(uint64)-8)
        done() # Inspect the whole interval before any successor; no prefix remapping on HUH.
  let access = if mode == 0: PageAccess.Inaccessible
    elif mode in [1'u64, 3]: PageAccess.ReadOnly else: PageAccess.ReadWrite
  let changed = source.memory.withPageRange(PageIndex(uint32(first)), PageIndex(uint32(past)),
    access, if mode < 3: PageContent.Zeroed else: PageContent.Preserved)
  if changed.error == MachineError.LimitExceeded: fail(InnerMachineError.LimitExceeded)
  if changed.error != MachineError.None: fail(InnerMachineError.InvalidContext)
  var slots = newSeqOfCap[InnerData](data.slots.len)
  for slot in data.slots:
    if slot.id == id:
      var info = slot.info
      info.memory = changed.value # Replace RAM alone; code, PC and block-charged flag retain original provenance.
      slots.add(InnerData(info: info, size: slot.size, id: slot.id))
    else:
      slots.add(slot) # Other machines remain shared immutable owners.
  transition.machines = InnerMachines(data: MapData(slots: slots, bytes: data.bytes,
      limits: data.limits))
  transition.response.registers[7] = RegisterValue(0)
  done()

proc transferInner(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limit: MemoryByteLimit, peek: bool): InnerMachineResult[
        InnerMachineTransition] =
  ## Share Omega_P/O ordering while selecting opposite read/write endpoints in one private synchronous transition.
  template fail(reason: InnerMachineError) =
    return InnerMachineResult[InnerMachineTransition](status: reason)
  let data = machines.data
  if data == nil: fail(InnerMachineError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None: fail(
      InnerMachineError.InvalidMemory)
  let size = uint64(registers[10])
  let linear = if peek: 336'u64 else: 224'u64
  let base = if peek: 377'u64 else: 297'u64
  # The largest whole-domain price is <2^63; divide before multiplying the untrusted count.
  let cost = base+(size div 1024)*linear+((size mod 1024)*linear+1023) div 1024
  let credit = uint64(gas)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if credit < cost:
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(cost-credit)
    done() # Underfunding changes no arguments, page bytes or map owners.
  transition.response.gas = MachineGas(credit-cost)
  let caller = MemoryAddress(uint64(registers[8]))
  let inner = MemoryAddress(uint64(registers[9]))
  let length = MemoryLength(size)
  let checked = if peek: memory.writableRange(caller, length)
    else: memory.readableRange(caller, length)
  case checked.error
  of MachineError.None:
    discard # Whole caller permissions precede both inner lookup and local copy limits.
  of MachineError.Fault, MachineError.InvalidRange:
    transition.response.action = HostAction.Panic
    done() # An inaccessible caller suffix cannot expose a successful prefix or WHO.
  else:
    fail(InnerMachineError.InvalidMemory)
  let id = uint64(registers[7])
  let found = machines.innerMachine(InnerMachineId(id))
  if found.error == InnerMachineError.Missing:
    transition.response.registers[7] = RegisterValue(high(uint64)-3)
    done() # Only a fully accessible caller interval may reach WHO.
  let source = found.value.memory
  let permitted = if peek: source.readableRange(inner, length)
    else: source.writableRange(inner, length)
  case permitted.error
  of MachineError.None:
    discard # Preflight the complete inner interval before allocating/copying either endpoint.
  of MachineError.Fault, MachineError.InvalidRange:
    transition.response.registers[7] = RegisterValue(high(uint64)-2)
    done() # OOB preserves caller and inner bytes, even on a partly accessible range.
  else:
    fail(InnerMachineError.InvalidContext)
  if size > uint64(limit): fail(InnerMachineError.LimitExceeded) # A local refusal never impersonates panic/WHO/OOB.
  let bytes = if peek: source.readBytes(inner, length, limit) else: memory.readBytes(caller, length, limit)
  if bytes.error != MachineError.None: fail(InnerMachineError.InvalidContext) # Immutable preflights proved all ranges/caps.
  let written = if peek: memory.writeBytes(caller, bytes.value, limit)
    else: source.writeBytes(inner, bytes.value, limit)
  if written.error != MachineError.None: fail(InnerMachineError.InvalidContext) # No partial successor is published on invariant failure.
  if peek:
    transition.response.memory = written.value # Peek changes only outer RAM; the invocation map remains the original owner.
  else:
    var slots = newSeqOfCap[InnerData](data.slots.len)
    for slot in data.slots:
      if slot.id == id:
        var info = slot.info
        info.memory = written.value
        slots.add(InnerData(info: info, size: slot.size,
            id: slot.id)) # Poke replaces only the selected RAM snapshot.
      else:
        slots.add(slot) # Unselected machines share their untouched immutable owners.
    transition.machines = InnerMachines(data: MapData(slots: slots, bytes: data.bytes,
        limits: data.limits))
  transition.response.registers[7] = RegisterValue(0)
  done()

proc innerPeekResponse*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limit: MemoryByteLimit): InnerMachineResult[InnerMachineTransition] =
  ## Evaluate host 10, copying inner readable bytes to an immutable writable caller-memory successor.
  transferInner(machines, gas, registers, memory, limit, true)

proc innerPokeResponse*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limit: MemoryByteLimit): InnerMachineResult[InnerMachineTransition] =
  ## Evaluate host 11, copying caller readable bytes to the selected immutable writable inner RAM successor.
  transferInner(machines, gas, registers, memory, limit, false)

proc innerInvokeResponse*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Execute Omega_K on the retained program/RAM/PC/charged flag, stopping before any inner host dispatch.
  template fail(reason: InnerMachineError) =
    return InnerMachineResult[InnerMachineTransition](status: reason)
  let data = machines.data
  if data == nil: fail(InnerMachineError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None: fail(
      InnerMachineError.InvalidMemory)
  let address = MemoryAddress(uint64(registers[8]))
  let writable = memory.writableRange(address, MemoryLength(112))
  var requested = 0'u64
  var innerRegisters = default(RegisterFile)
  case writable.error
  of MachineError.None:
    let bytes = memory.readBytes(address, MemoryLength(112), MemoryByteLimit(112)).value
    for word in 0..<14:
      var value = 0'u64
      for octet in 0..<8: value = value or (uint64(bytes[word*8+octet]) shl (
          octet*8)) # Fixed E8 little-endian words preserve high bits.
      if word == 0: requested = value
      else: innerRegisters[word-1] = RegisterValue(
          value) # Thirteen copied guest registers cannot replace code or RAM owners.
  of MachineError.Fault, MachineError.InvalidRange:
    discard # Bad frames contribute zero requested gas; affordability still precedes protocol panic.
  else:
    fail(InnerMachineError.InvalidMemory)
  let credit = uint64(gas)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if credit < 968 or requested > credit-968:
    var debt = 0'u64
    if requested > credit:
      let difference = requested-credit
      if difference > 0x8000000000000000'u64-968: fail(InnerMachineError.LimitExceeded)
      debt = difference+968 # Prove canonical negative magnitude before addition; requested+968 may not fit uint64.
    else:
      debt = 968-(credit-requested) # Failed affordability proves the nonnegative difference is less than the base price.
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(debt)
    done() # Underfunding returns original frame, arguments and map, even for missing IDs or bad frames.
  let reserved = credit-968-requested
  transition.response.gas = MachineGas(reserved)
  if writable.error != MachineError.None:
    transition.response.action = HostAction.Panic
    done() # A fully charged invalid frame panics before identity lookup.
  let id = uint64(registers[7])
  let found = machines.innerMachine(InnerMachineId(id))
  if found.error == InnerMachineError.Missing:
    transition.response.registers[7] = RegisterValue(high(uint64)-3)
    done() # WHO retains the frame and consumes the complete reservation without refund.
  let source = found.value
  let initial = captureTerminalMachine(source.program, source.memory,
    MachineInfo(pc: source.pc, gas: MachineGas(requested), gasDeficit: GasDeficit(0),
      blockCharged: source.blockCharged, registers: innerRegisters))
  if initial.error != MachineError.None: fail(InnerMachineError.InvalidContext)
  let evaluated = execute(initial.value, data.limits.steps, data.limits.cycles)
  if evaluated.error != StepError.None:
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.ExecutionFailure,
      reason: evaluated.error) # No tentative frame, nested state or refund escapes a local engine refusal.
  let stopped = evaluated.value
  let cpu = stopped.machine.machineInfo.value
  if uint64(cpu.gasDeficit) != 0 or uint64(cpu.gas) > requested:
    fail(InnerMachineError.InvalidContext) # Raw guest-only Psi cannot create host debt or increase its allowance.
  var info = source
  info.pc = cpu.pc
  info.blockCharged = cpu.blockCharged
  info.memory = stopped.machine.memoryOf.value
  case stopped.exit
  of StepExit.Halt:
    transition.response.registers[7] = RegisterValue(0) # Recursive Psi already normalizes terminal PC to zero.
  of StepExit.Panic:
    transition.response.registers[7] = RegisterValue(1)
  of StepExit.Fault:
    transition.response.registers[7] = RegisterValue(2)
    transition.response.registers[8] = RegisterValue(uint64(uint32(
        stopped.faultPage))) # Preserve the physical aligned byte address.
  of StepExit.Host:
    transition.response.registers[7] = RegisterValue(3)
    transition.response.registers[8] = RegisterValue(uint64(stopped.hostCall))
    let item = instruction(source.program, cpu.pc).value
    info.pc = CodeAddress(uint64(cpu.pc)+1+uint64(
        item.skip)) # Valid owned code extent bounds this successor addition.
  of StepExit.OutOfGas:
    transition.response.registers[7] = RegisterValue(
        4) # Preserve causing PC/charged flag and any unspent block credit.
  else:
    fail(InnerMachineError.InvalidContext)
  var frame = default(array[112, byte])
  for word in 0..<14:
    let value = if word == 0: uint64(cpu.gas) else: uint64(cpu.registers[word-1])
    for octet in 0..<8: frame[word*8+octet] = byte((value shr (octet*8)) and
        255) # Encode all fourteen posterior E8 words.
  let written = memory.writeBytes(address, frame, MemoryByteLimit(112))
  if written.error != MachineError.None: fail(InnerMachineError.InvalidContext) # The immutable frame preflight proved the complete write.
  var slots = newSeqOfCap[InnerData](data.slots.len)
  for slot in data.slots:
    if slot.id == id: slots.add(InnerData(info: info, size: slot.size,
        id: slot.id)) # RAM/PC/flag share one completed segment certificate.
    else: slots.add(slot) # Retain all other machines unchanged.
  transition.machines = InnerMachines(data: MapData(slots: slots, bytes: data.bytes,
      limits: data.limits))
  transition.response.memory = written.value
  transition.response.gas = MachineGas(reserved+uint64(
      cpu.gas)) # cpu.gas<=requested proves refund cannot overflow or mint caller gas.
  done()
