# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 machine snapshots and sparse memory; see spec/pvm-machine.md. Published owners are
## immutable, acyclic ARC graphs. Updates return independent snapshots.
##
## Exposes immutable Memory/Machine snapshots, page capture/replacement, checked scalar
## load/store and copied register/state updates.

import ./program

type
  # Guest effective addresses retain the register domain until cyclic 32-bit memory access.
  MemoryAddress* = distinct uint64
  # Fault reasons contain a physical aligned byte address, not a page ordinal.
  PageAddress* = distinct uint32
  # Page ordinals must be below 2^20; construction validates before indexing or allocation.
  PageIndex* = distinct uint32
  # Local allocation policy bounds materialized pages, including inaccessible retained pages.
  PageLimit* = distinct uint32
  # Supported scalar access sizes are 1, 2, 4 and 8; other values return InvalidWidth.
  AccessWidth* = distinct byte
  # Register values are independent of decoded immediates and addresses.
  RegisterValue* = distinct uint64
  # PVM gas is unsigned here; signed host-call gas accounting is outside this increment.
  MachineGas* = distinct uint64
  # Every machine snapshot contains exactly thirteen copied register values.
  RegisterFile* = array[13, RegisterValue]
  # Writable pages are also readable; inaccessible pages may retain bytes for later remapping.
  PageAccess* {.pure.} = enum
    Inaccessible, ReadOnly, ReadWrite
  # Caller-owned page input is copied and never retained by reference.
  PageImage* = object
    index*: PageIndex
    access*: PageAccess
    bytes*: array[4096, byte]
  # Local API failures are distinct from guest panic/fault, including an explicit specification gate.
  MachineError* {.pure.} = enum
    Uninitialized, None, InvalidOwner, InvalidPage, UnsortedPages, LimitExceeded,
    InvalidWidth, InvalidRegister, InvalidProgram, Panic, Fault, AmbiguousAccessOrder
  # Fault addresses belong to the failure reason; other failures carry no value or progress.
  MachineResult*[T] = object
    case status: MachineError
    of None:
      # Only success publishes a complete value or owner.
      completed: T
    of Fault:
      # The failing physical page is part of the typed guest fault reason.
      failedPage: PageAddress
    else:
      # No partial state or byte count escapes a local failure or guest panic.
      discard
  # Each retained page is immutable after publication; snapshots can share unchanged pages.
  PageData = ref object
    image: PageImage
  # Sorted sparse page references avoid allocating the entire 4 GiB guest address space.
  MemoryData = ref object
    pages: seq[PageData]
    limit: PageLimit
  # A default handle is invalid; captureMemory([], ...) creates valid empty memory.
  Memory* = object
    data: nil MemoryData
  # Copied CPU state has no pointer into registers or mutable backing storage.
  MachineInfo* = object
    pc*: CodeAddress
    gas*: MachineGas
    blockCharged*: bool
    registers*: RegisterFile
  # Immutable machine root retains program and memory owners without any back-reference.
  MachineData = ref object
    program: Program
    memory: Memory
    info: MachineInfo
  # Copying the public handle retains the same immutable snapshot, never a mutable machine alias.
  Machine* = object
    data: nil MachineData

# Status inspection cannot retag or forge a result.
func error*[T](r: MachineResult[T]): MachineError = r.status
# A successful result alone grants access to its copied payload.
func value*[T](r: MachineResult[T]): T {.inline, requires: r.status == MachineError.None.} =
  r.completed
# A page address is meaningful only for a guest Fault, never for API failures or panic.
func faultPage*[T](r: MachineResult[T]): PageAddress {.inline, requires: r.status ==
    MachineError.Fault.} =
  r.failedPage

# Propagate only a failure reason across payload types without leaking partial success state.
func failure[T, U](r: MachineResult[U]): MachineResult[T] {.requires: r.status !=
    MachineError.None.} =
  # Fault is the sole failure with an associated reason parameter.
  if r.status == MachineError.Fault:
    return MachineResult[T](status: MachineError.Fault, failedPage: r.failedPage)
  MachineResult[T](status: r.status)

# Validate sorted unique physical page ordinals and the allocation limit before capturing any page.
proc captureMemory*(pages: openArray[PageImage], limit: PageLimit): MachineResult[Memory] =
  # A local resource ceiling is not a consensus memory size or gas limit.
  if uint64(pages.len) > uint64(uint32(limit)):
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  # Validate the complete shape before allocating private copies.
  for i in 0..<pages.len:
    # The address space contains exactly 2^20 pages of 4096 bytes.
    if uint32(pages[i].index) >= 0x100000'u32:
      return MachineResult[Memory](status: MachineError.InvalidPage)
    # Strict ordering also excludes duplicates and makes lookup deterministic.
    if i > 0 and uint32(pages[i - 1].index) >= uint32(pages[i].index):
      return MachineResult[Memory](status: MachineError.UnsortedPages)
  var owned = newSeqOfCap[PageData](pages.len)
  # Fixed arrays copy their bytes; no caller-owned pointer survives this call.
  for i in 0..<pages.len: owned.add(PageData(image: pages[i]))
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: owned, limit: limit)))

# Locate the first stored page whose index is at least the requested ordinal.
func lowerBound(data: MemoryData, index: uint32): int =
  var first = 0
  var last = data.pages.len
  # Difference-based midpoint arithmetic avoids overflowing endpoint sums.
  while first < last:
    let middle = first + (last - first) div 2
    # Discard the lower half only when its page precedes the requested one.
    if uint32(data.pages[middle].image.index) < index: first = middle + 1
    else:
      # Equality stays in the retained interval so the result is an insertion position too.
      last = middle
  first

# Return a copied page, representing absent pages as inaccessible all-zero storage.
proc pageImage*(memory: Memory, index: PageIndex): MachineResult[PageImage] =
  # Default owners never behave like valid empty memory.
  if memory.data == nil: return MachineResult[PageImage](status: MachineError.InvalidOwner)
  # Page ordinals must be validated before converting them to addresses.
  if uint32(index) >= 0x100000'u32:
    return MachineResult[PageImage](status: MachineError.InvalidPage)
  let data = memory.data
  let at = lowerBound(data, uint32(index))
  # A present page copies its bytes and permission; callers can mutate that copy safely.
  if at < data.pages.len and uint32(data.pages[at].image.index) == uint32(index):
    return MachineResult[PageImage](status: MachineError.None, completed: data.pages[at].image)
  MachineResult[PageImage](status: MachineError.None, completed: PageImage(index: index,
    access: PageAccess.Inaccessible, bytes: default(array[4096, byte])))

# Replace or insert one environment-owned page, preserving all other pages and the prior snapshot.
# This is setup/remapping, not a guest write: it may change read-only/inaccessible page contents.
proc withPage*(memory: Memory, page: PageImage): MachineResult[Memory] =
  # All local errors precede both the reference-vector and page allocation.
  if memory.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  if uint32(page.index) >= 0x100000'u32:
    # No out-of-domain ordinal may enter a validated memory owner.
    return MachineResult[Memory](status: MachineError.InvalidPage)
  let data = memory.data
  let at = lowerBound(data, uint32(page.index))
  let replacing = at < data.pages.len and uint32(data.pages[at].image.index) == uint32(page.index)
  # Replacing a page at the ceiling is permitted; inserting another is not.
  if not replacing and uint64(data.pages.len) >= uint64(uint32(data.limit)):
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  var pages = newSeqOfCap[PageData](data.pages.len + int(not replacing))
  # Reuse immutable page references outside the one replacement/insertion slot.
  for i in 0..<at: pages.add(data.pages[i])
  pages.add(PageData(image: page))
  # Insertion shifts the suffix; replacement leaves its positions unchanged.
  for i in at + int(replacing)..<data.pages.len:
    pages.add(data.pages[i])
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pages, limit: data.limit)))

# Resolve a guest scalar byte cyclically without overflowing a 64-bit input address.
func byteAddress(address: MemoryAddress, offset: int): uint32 =
  uint32(((uint64(address) and 0xffffffff'u64) + uint64(offset)) and 0xffffffff'u64)

# Preflight every touched byte before a load or write. Gas/execution ordering is not performed here.
proc inspect(memory: Memory, address: MemoryAddress, width: AccessWidth,
    writing: bool): MachineResult[bool] =
  # Owner/width errors are local API failures, not fabricated PVM exits.
  if memory.data == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  if byte(width) notin [1'u8, 2'u8, 4'u8, 8'u8]:
    # Invalid scalar widths cannot accidentally become unbounded scans or shifts.
    return MachineResult[bool](status: MachineError.InvalidWidth)
  let data = memory.data
  var hasFault = false
  var firstFault = PageAddress(0)
  var protected = false
  # At most eight byte checks cover all scalar load/store instructions, including page crossings.
  for i in 0..<int(byte(width)):
    let physical = byteAddress(address, i)
    # The low 64 KiB is protected even if an environment supplied accessible pages there.
    if physical < 0x10000'u32:
      protected = true
    else:
      # Permissions are attached to pages; writable implies readable in the pinned definition.
      let index = physical div 4096
      let at = lowerBound(data, index)
      var access = PageAccess.Inaccessible
      # A missing sparse page has inaccessible permissions and zero underlying bytes.
      if at < data.pages.len and uint32(data.pages[at].image.index) == index:
        access = data.pages[at].image.access
      # Remember the first inaccessible byte in the original ascending access sequence.
      if not hasFault and (access == PageAccess.Inaccessible or
          (writing and access != PageAccess.ReadWrite)):
        hasFault = true
        firstFault = PageAddress(physical and 0xfffff000'u32)
  # At a wrap, prose says protected-low panic while the formal minimum can select a high-page fault.
  # Refuse to invent precedence; this local error is an explicit specification gate, not a VM exit.
  if protected and hasFault and uint64(address) mod 0x100000000'u64 >= 0x10000'u64:
    return MachineResult[bool](status: MachineError.AmbiguousAccessOrder)
  # An access containing protected bytes and no earlier fault always panics.
  if protected: return MachineResult[bool](status: MachineError.Panic)
  # Fault addresses are aligned physical byte addresses, never page ordinals.
  if hasFault: return MachineResult[bool](status: MachineError.Fault, failedPage: firstFault)
  MachineResult[bool](status: MachineError.None, completed: true)

# Load a little-endian unsigned scalar; sign extension belongs to the eventual instruction executor.
proc load*(memory: Memory, address: MemoryAddress, width: AccessWidth): MachineResult[
    RegisterValue] =
  let checked = inspect(memory, address, width, false)
  # A failed preflight exposes no partially read value.
  if checked.error != MachineError.None: return failure[RegisterValue, bool](checked)
  # Reestablish ownership for the compiler's supported non-nil analysis.
  if memory.data == nil: return MachineResult[RegisterValue](status: MachineError.InvalidOwner)
  let data = memory.data
  var value = 0'u64
  # Successful preflight proved every physical page is present and readable.
  for i in 0..<int(byte(width)):
    let physical = byteAddress(address, i)
    let at = lowerBound(data, physical div 4096)
    value = value or (uint64(data.pages[at].image.bytes[int(physical mod 4096)]) shl (8 * i))
  MachineResult[RegisterValue](status: MachineError.None, completed: RegisterValue(value))

# Store the low width bytes atomically into a new owner; no source snapshot can change on failure.
proc store*(memory: Memory, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[Memory] =
  let checked = inspect(memory, address, width, true)
  # Validate the entire access before cloning or changing even the first touched page.
  if checked.error != MachineError.None: return failure[Memory, bool](checked)
  # A separate owner check establishes non-nil storage for subsequent compiler analysis.
  if memory.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  let data = memory.data
  var pages = newSeqOfCap[PageData](data.pages.len)
  # The new reference vector initially shares only immutable pages with the old owner.
  for i in 0..<data.pages.len: pages.add(data.pages[i])
  var previous = -1
  # At most two contiguous pages are copied; byte writes cannot reach shared page objects.
  for i in 0..<int(byte(width)):
    let physical = byteAddress(address, i)
    let at = lowerBound(data, physical div 4096)
    # Clone on first entry to each page, preserving earlier bytes written to that clone.
    if at != previous:
      pages[at] = PageData(image: data.pages[at].image)
      previous = at
    pages[at].image.bytes[int(physical mod 4096)] = byte((uint64(value) shr (8 * i)) and 255)
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pages, limit: data.limit)))

# Capture a validated entry location and copied CPU values; this is not standard JAM initialization.
proc captureMachine*(program: Program, memory: Memory, info: MachineInfo): MachineResult[Machine] =
  # Empty/default memory must be distinguished from a valid all-inaccessible memory snapshot.
  if memory.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  # Reuse the base PR's instruction-boundary validation without re-decoding or copying its program.
  if instruction(program, info.pc).error != ProgramError.None:
    return MachineResult[Machine](status: MachineError.InvalidProgram)
  MachineResult[Machine](status: MachineError.None,
    completed: Machine(data: MachineData(program: program, memory: memory, info: info)))

# Copy all CPU values; changes to this returned value cannot affect its source machine.
proc machineInfo*(machine: Machine): MachineResult[MachineInfo] =
  # Default handles do not imply zero registers or successful execution.
  if machine.data == nil: return MachineResult[MachineInfo](status: MachineError.InvalidOwner)
  MachineResult[MachineInfo](status: MachineError.None, completed: machine.data.info)

# Retain the immutable memory handle for inspection or environment-driven page recovery.
proc memoryOf*(machine: Machine): MachineResult[Memory] =
  # Ownership must be established before extracting a child handle.
  if machine.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  MachineResult[Memory](status: MachineError.None, completed: machine.data.memory)

# Replace only the memory owner after an environment repair; CPU state/program remain unchanged.
proc withMemory*(machine: Machine, memory: Memory): MachineResult[Machine] =
  # Neither parent nor replacement may be an uninitialized owner.
  if machine.data == nil or memory.data == nil:
    return MachineResult[Machine](status: MachineError.InvalidOwner)
  MachineResult[Machine](status: MachineError.None, completed: Machine(data: MachineData(
    program: machine.data.program, memory: memory, info: machine.data.info)))

# Update one copied register without executing an instruction or charging gas.
proc withRegister*(machine: Machine, index: RegisterIndex,
    value: RegisterValue): MachineResult[Machine] =
  # The owner and public nominal index both require validation before accessing the fixed array.
  if machine.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  if byte(index) >= 13:
    # Operand decoding saturates indices, but direct API callers can construct invalid nominal values.
    return MachineResult[Machine](status: MachineError.InvalidRegister)
  let data = machine.data
  var info = data.info
  info.registers[int(byte(index))] = value
  MachineResult[Machine](status: MachineError.None, completed: Machine(data: MachineData(
    program: data.program, memory: data.memory, info: info)))

# A successful memory update replaces only memory; every CPU field survives unchanged.
proc store*(machine: Machine, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[Machine] =
  # A default machine cannot manufacture a successful update from default memory.
  if machine.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  let data = machine.data
  let updated = store(data.memory, address, width, value)
  # Forward the complete reason, including a fault address, without publishing a partial machine.
  if updated.error != MachineError.None: return failure[Machine, Memory](updated)
  withMemory(machine, updated.value)
