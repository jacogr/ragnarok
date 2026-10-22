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
    Uninitialized, None, InvalidContext, InvalidMemory, LimitExceeded, Missing, UnsupportedSource, ExecutionFailure
  InnerModuleHandle* = distinct uint64 ## Shared compiled-module identity is distinct from a running instance ID.
  InnerMachineInfo* = object ## Copied metadata and immutable child owners cannot rewrite the original map.
    program*: Program
    memory*: Memory
    pc*: CodeAddress
    blockCharged*: bool
    moduleHandle*: InnerModuleHandle
  ModuleData = object ## Immutable program capture retained by its published handle or live instances.
    handle: uint64
    program: Program
    size: uint64
  InnerData = ref object ## One immutable program/memory pair has no back-reference to its map.
    info: InnerMachineInfo
    size: uint64
    id: uint64
  MapData = ref object ## Sorted immutable slots are bounded by 63, independently of full-width guest IDs.
    slots: seq[InnerData]
    modules: seq[ModuleData]
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
  InnerMachines(data: MapData(slots: @[], modules: @[], bytes: 0, limits: limits))
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

proc retainedModule(machines: MapData, handle: uint64): bool =
  ## Handles retained by live instances remain occupied after their catalogue entry is expunged.
  for item in machines.modules:
    if item.handle == handle: return true # A catalogue entry owns one immutable prepared module.
  for item in machines.slots:
    if uint64(item.info.moduleHandle) == handle: return true # Live instances retain the underlying program.
  false

proc compileInnerModule*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Prepare an interpreted program module from guest memory; database mode is an explicit adapter gate.
  template fail(reason: InnerMachineError) =
    return InnerMachineResult[InnerMachineTransition](status: reason)
  let data = machines.data
  if data == nil: fail(InnerMachineError.InvalidContext)
  if pageImage(memory, PageIndex(0)).error != MachineError.None: fail(
      InnerMachineError.InvalidMemory)
  let mode = uint64(registers[7])
  let size = uint64(registers[9])
  let rate = if mode == 0: 264'u64 elif mode == 1: 366'u64 else: 0'u64
  # Division before multiplication proves every u64-sized source price fits unsigned gas.
  let cost = 1862'u64+(size div 1024)*rate+((size mod 1024)*rate+1023) div 1024
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: gas, gasDeficit: GasDeficit(0),
      registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if uint64(gas) < cost:
    transition.response.action = HostAction.OutOfGas
    transition.response.gas = MachineGas(0)
    done() # Gas precedes handle limits and source access.
  transition.response.gas = MachineGas(uint64(gas)-cost) # The affordability check proves subtraction.
  var handle = 0'u64
  while handle < 128 and retainedModule(data, handle):
    inc handle # At most128 handles exist in the catalogue/live-instance union.
  if handle == 128:
    transition.response.registers[7] = RegisterValue(high(uint64)-4)
    done() # FULL takes precedence over source validation.
  if mode == 1:
    fail(InnerMachineError.UnsupportedSource) # Historical database authorization belongs to the outer refinement adapter.
  if mode != 0:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # Unknown source modes are protocol HUH, not missing host functions.
  if size > uint64(data.limits.program) or data.bytes > uint64(data.limits.total) or
      size > uint64(data.limits.total)-data.bytes:
    fail(InnerMachineError.LimitExceeded) # Prove all retained/copy allocation extents before source reads.
  let copied = readBytes(memory, MemoryAddress(uint64(registers[8])), MemoryLength(size),
    MemoryByteLimit(uint64(data.limits.program)))
  case copied.error
  of MachineError.None:
    discard # The complete original source bytes are stable and independently owned for parsing.
  of MachineError.Fault, MachineError.InvalidRange:
    transition.response.action = HostAction.Panic
    done() # Inaccessible memory publishes neither a module handle nor partial parsing state.
  of MachineError.LimitExceeded:
    fail(InnerMachineError.LimitExceeded)
  else:
    fail(InnerMachineError.InvalidMemory)
  let parsed = decodeJamProgram(copied.value, CodeAddress(0), data.limits.program,
      data.limits.jumps)
  if parsed.error == ProgramError.LimitExceeded: fail(InnerMachineError.LimitExceeded)
  if parsed.error != ProgramError.None:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # HUH retains the complete original map for malformed program bytes.
  var modules = newSeqOfCap[ModuleData](data.modules.len+1)
  for item in data.modules:
    modules.add(item) # Copy the catalogue descriptor; immutable program owners stay shared.
  modules.add(ModuleData(handle: handle, program: parsed.value, size: size))
  transition.machines = InnerMachines(data: MapData(slots: data.slots, modules: modules,
    bytes: data.bytes+size, limits: data.limits))
  transition.response.registers[7] = RegisterValue(handle)
  done()

proc createInnerMachine*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Instantiate only a previously compiled module handle at the requested executable entry.
  let data = machines.data
  if data == nil: return InnerMachineResult[InnerMachineTransition](
      status: InnerMachineError.InvalidContext)
  if pageImage(memory, PageIndex(0)).error != MachineError.None:
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.InvalidMemory)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: gas, gasDeficit: GasDeficit(0),
      registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if uint64(gas) < 1862:
    transition.response.action = HostAction.OutOfGas
    transition.response.gas = MachineGas(0)
    done() # Affordability precedes every protocol table mutation.
  transition.response.gas = MachineGas(uint64(gas)-1862) # The preceding comparison proves subtraction.
  if data.slots.len >= 63:
    transition.response.registers[7] = RegisterValue(high(uint64)-4)
    done() # Protocol instance capacity precedes module-handle and entry validation.
  let handle = uint64(registers[7])
  var found = false
  var program = default(Program)
  var size = 0'u64
  for item in data.modules:
    if item.handle == handle:
      program = item.program
      size = item.size
      found = true
      break # The catalogue contains at most one module with this handle.
  if not found:
    transition.response.registers[7] = RegisterValue(high(uint64)-3)
    done() # WHO cannot instantiate a handle retained only by another running instance.
  let entry = CodeAddress(uint64(registers[8]))
  if instructionOpcode(program, entry).error != ProgramError.None:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # HUH retains modules and instances on invalid entry.
  if uint64(data.slots.len) >= uint64(uint32(data.limits.items)):
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.LimitExceeded)
  var at = 0
  while at < data.slots.len and data.slots[at].id == uint64(at): inc at # Select the smallest missing instance ID.
  var slots = newSeqOfCap[InnerData](data.slots.len+1)
  for index in 0..<at: slots.add(data.slots[index]) # Preserve the sorted prefix without mutable aliases.
  slots.add(InnerData(info: InnerMachineInfo(program: program,
    memory: captureMemory([], data.limits.pages).value, pc: entry, blockCharged: false,
    moduleHandle: InnerModuleHandle(handle)), size: size, id: uint64(at)))
  for index in at..<data.slots.len: slots.add(data.slots[index]) # Retain every independent existing instance.
  transition.machines = InnerMachines(data: MapData(slots: slots, modules: data.modules,
    bytes: data.bytes, limits: data.limits))
  transition.response.registers[7] = RegisterValue(uint64(at))
  done()

proc expungeInnerMachine*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Remove a running instance (mode0) or catalogue module (mode1), retaining handles still used by instances.
  let data = machines.data
  if data == nil: return InnerMachineResult[InnerMachineTransition](
      status: InnerMachineError.InvalidContext)
  if pageImage(memory, PageIndex(0)).error != MachineError.None:
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.InvalidMemory)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: gas, gasDeficit: GasDeficit(0),
      registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if uint64(gas) < 335:
    transition.response.action = HostAction.OutOfGas
    transition.response.gas = MachineGas(0)
    done() # Affordability precedes every protocol table mutation.
  transition.response.gas = MachineGas(uint64(gas)-335) # The preceding comparison proves subtraction.
  let mode = uint64(registers[7])
  let id = uint64(registers[8])
  var handle = 0'u64
  var size = 0'u64
  var found = false
  if mode == 0:
    let selected = innerMachine(machines, InnerMachineId(id))
    if selected.error == InnerMachineError.None:
      handle = uint64(selected.value.moduleHandle)
      transition.response.registers[7] = RegisterValue(uint64(selected.value.pc))
      found = true
    var slots = newSeqOfCap[InnerData](data.slots.len)
    for slot in data.slots:
      if slot.id == id:
        size = slot.size # Each matching instance retains the exact immutable module byte extent.
      else:
        slots.add(slot) # Other instance owners and their module handles remain independent.
    if found:
      var retained = false
      for item in data.modules:
        if item.handle == handle: retained = true # The catalogue still owns this module.
      for slot in slots:
        if uint64(slot.info.moduleHandle) == handle: retained = true # Another instance still owns this module.
      transition.machines = InnerMachines(data: MapData(slots: slots, modules: data.modules,
        bytes: data.bytes-(if retained: 0'u64 else: size), limits: data.limits))
  elif mode == 1:
    var modules = newSeqOfCap[ModuleData](data.modules.len)
    for item in data.modules:
      if item.handle == id:
        found = true
        size = item.size
      else:
        modules.add(item) # Expunging a catalogue entry never removes a live instance.
    if found:
      var retained = false
      for slot in data.slots:
        if uint64(slot.info.moduleHandle) == id: retained = true # A live owner keeps both bytes and handle occupied.
      transition.machines = InnerMachines(data: MapData(slots: data.slots, modules: modules,
        bytes: data.bytes-(if retained: 0'u64 else: size), limits: data.limits))
      transition.response.registers[7] = RegisterValue(0)
  else:
    transition.response.registers[7] = RegisterValue(high(uint64)-8)
    done() # Unsupported modes return HUH after the fixed host charge.
  if not found: transition.response.registers[7] = RegisterValue(high(uint64)-3) # WHO publishes no map change.
  done()

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
  let tooLarge = linear != 0 and count > (high(uint64)-base) div linear
  let cost = if tooLarge: 0'u64 else: base+count*linear
  let credit = uint64(gas)
  var transition = InnerMachineTransition(machines: machines,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0),
      gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  template done() =
    return InnerMachineResult[InnerMachineTransition](status: InnerMachineError.None,
        completed: transition)
  if tooLarge or credit < cost:
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(0)
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
  transition.machines = InnerMachines(data: MapData(slots: slots, modules: data.modules,
      bytes: data.bytes, limits: data.limits))
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
    transition.response.gasDeficit = GasDeficit(0)
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
    transition.machines = InnerMachines(data: MapData(slots: slots, modules: data.modules,
        bytes: data.bytes, limits: data.limits))
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
    # Compare before addition: an unaffordable reservation saturates to zero even if requested+968 exceeds u64.
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(0)
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
  if uint64(cpu.gas) > requested:
    fail(InnerMachineError.InvalidContext) # Raw guest-only Psi cannot increase its allowance.
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
  transition.machines = InnerMachines(data: MapData(slots: slots, modules: data.modules,
      bytes: data.bytes, limits: data.limits))
  transition.response.memory = written.value
  transition.response.gas = MachineGas(reserved+uint64(
      cpu.gas)) # cpu.gas<=requested proves refund cannot overflow or mint caller gas.
  done()
