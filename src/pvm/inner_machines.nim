# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 refinement hosts 9/12/14 own immutable invocation-local inner-machine lifecycle and pages.
## Exposes bounded empty-map capture, copied inspection and atomic lifecycle/page response-successor transitions.

import ./[machine, program, step]

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
  InnerMachineError* {.pure.} = enum ## Local/default refusals expose no response or partially modified map.
    Uninitialized, None, InvalidContext, InvalidMemory, LimitExceeded, Missing
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
    else:
      discard                     # Local failures retain neither scratch bytes nor a manufactured protocol result.

func error*[T](outcome: InnerMachineResult[T]): InnerMachineError =
  ## Inspect the reason without writable tag access.
  outcome.status
func value*[T](outcome: InnerMachineResult[T]): T
    {.requires: outcome.status == InnerMachineError.None.} =
  ## Extract only complete successful owners or transitions, including protocol-error responses.
  outcome.completed
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
  let parsed = decodeProgram(bytes.value, CodeAddress(uint64(registers[9])), limits.program, limits.jumps)
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
