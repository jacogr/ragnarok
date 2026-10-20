# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 machine snapshots and sparse memory; see spec/pvm-machine.md. Published owners are
## immutable, acyclic ARC graphs. Updates return independent snapshots.
##
## Exposes immutable Memory/Machine snapshots, page capture/replacement, checked scalar
## load/store, bounded host readBytes/writeBytes, allocation-free readableRange/writableRange,
## programOf/memoryOf child access, copied state
## updates, writable-page range counting/mapping, atomic zero/remap/free ranges and terminal-state capture.

import ./program

type
  MemoryAddress* = distinct uint64 ## Guest effective addresses retain the register domain until cyclic 32-bit memory access.
  PageAddress* = distinct uint32 ## Fault reasons contain a physical aligned byte address, not a page ordinal.
  PageIndex* = distinct uint32 ## Page ordinals are below 2^20; validated exclusive range endpoints may equal 2^20.
  PageCount* = distinct uint32 ## A count of pages is distinct from an ordinal, byte length and local allocation policy.
  PageLimit* = distinct uint32 ## Local allocation policy bounds materialized pages, including inaccessible retained pages.
  AccessWidth* = distinct byte ## Supported scalar access sizes are 1, 2, 4 and 8; other values return InvalidWidth.
  MemoryLength* = distinct uint64 ## Natural byte-range length for host memory operations, never a scalar instruction width.
  MemoryByteLimit* = distinct uint64 ## Local payload-copy ceiling; independent of guest lengths and page-allocation limits.
  RegisterValue* = distinct uint64 ## Register values are independent of decoded immediates and addresses.
  MachineGas* = distinct uint64 ## Nonnegative gas component; a terminal negative balance is represented separately by GasDeficit.
  GasDeficit* = distinct uint64 ## Magnitude of a negative terminal balance, at most 2^63; nonzero deficit requires zero gas.
  RegisterFile* = array[13, RegisterValue] ## Every machine snapshot contains exactly thirteen copied register values.
  PageAccess* {.pure.} = enum ## Writable pages are also readable; inaccessible pages may retain bytes for later remapping.
    Inaccessible, ReadOnly, ReadWrite
  PageContent* {.pure.} = enum ## Trusted page-range updates explicitly choose retained bytes or all-zero replacement.
    Preserved, Zeroed
  PageImage* = object ## Caller-owned page input is copied and never retained by reference.
    index*: PageIndex
    access*: PageAccess
    bytes*: array[4096, byte]
  MachineError* {.pure.} = enum ## Local API failures are distinct from guest panic/fault, including an explicit specification gate.
    Uninitialized, None, InvalidOwner, InvalidPage, UnsortedPages, LimitExceeded,
    InvalidWidth, InvalidRegister, InvalidProgram, Panic, Fault, AmbiguousAccessOrder, InvalidRange, InvalidGasState
  MachineResult*[T] = object ## Fault addresses belong to the failure reason; other failures carry no value or progress.
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
  Memory* = object ## A default handle is invalid; captureMemory([], ...) creates valid empty memory.
    data: nil MemoryData
  MachineInfo* = object ## Copied CPU state has no pointer into registers or mutable backing storage.
    pc*: CodeAddress
    gas*: MachineGas
    # Terminal negative magnitude; gas credit must be zero whenever this is nonzero.
    gasDeficit*: GasDeficit
    blockCharged*: bool
    registers*: RegisterFile
  # Immutable machine root retains program and memory owners without any back-reference.
  MachineData = ref object
    program: Program
    memory: Memory
    info: MachineInfo
  Machine* = object ## Copying the public handle retains the same immutable snapshot, never a mutable machine alias.
    data: nil MachineData

func error*[T](r: MachineResult[T]): MachineError =
  ## Status inspection cannot retag or forge a result.
  r.status
func value*[T](r: MachineResult[T]): T {.inline, requires: r.status == MachineError.None.} =
  ## A successful result alone grants access to its copied payload.
  r.completed
func faultPage*[T](r: MachineResult[T]): PageAddress {.inline, requires: r.status ==
    MachineError.Fault.} =
  ## A page address is meaningful only for a guest Fault, never for API failures or panic.
  r.failedPage

# Propagate only a failure reason across payload types without leaking partial success state.
func failure[T, U](r: MachineResult[U]): MachineResult[T] {.requires: r.status !=
    MachineError.None.} =
  # Fault is the sole failure with an associated reason parameter.
  if r.status == MachineError.Fault:
    return MachineResult[T](status: MachineError.Fault, failedPage: r.failedPage)
  MachineResult[T](status: r.status)

proc captureMemory*(pages: openArray[PageImage], limit: PageLimit): MachineResult[Memory] =
  ## Validate sorted unique physical page ordinals and the allocation limit before capturing any page.
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

proc pageImage*(memory: Memory, index: PageIndex): MachineResult[PageImage] =
  ## Return a copied page, representing absent pages as inaccessible all-zero storage.
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

proc withPage*(memory: Memory, page: PageImage): MachineResult[Memory] =
  ## Replace or insert one environment-owned page, preserving all other pages and the prior snapshot.
  ## This is setup/remapping, not a guest write: it may change read-only/inaccessible page contents.
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

proc writablePageCount*(memory: Memory, first, past: PageIndex): MachineResult[PageCount] =
  ## Count writable pages in [first, past), with an exclusive endpoint up to 2^20.
  ## Walk only retained pages; missing pages are inaccessible. This does not infer heap bounds.
  let data = memory.data
  if data == nil:
    # Default owners must not masquerade as an empty, valid address space.
    return MachineResult[PageCount](status: MachineError.InvalidOwner)
  if uint32(first) > uint32(past) or uint32(past) > 0x100000'u32:
    # Ordered endpoints prove both are in range before any lookup or subtraction.
    return MachineResult[PageCount](status: MachineError.InvalidRange)
  let start = lowerBound(data, uint32(first))
  let stop = lowerBound(data, uint32(past))
  var count = 0'u32
  for i in start..<stop:
    # Only writable retained pages contribute; read-only and inaccessible pages do not.
    if data.pages[i].image.access == PageAccess.ReadWrite:
      inc count # Unique ordinals bound the count by the physical page domain.
  MachineResult[PageCount](status: MachineError.None, completed: PageCount(count))

proc withWritablePages*(memory: Memory, first, past: PageIndex): MachineResult[Memory] =
  ## Atomically map [first, past) writable, preserving all retained bytes and outside permissions.
  ## Preflight the owner's complete page policy before allocation. Absent pages become zero-filled;
  ## unchanged page owners are shared. Callers must separately enforce host-call region/gas rules.
  let data = memory.data
  if data == nil:
    # No partial allocation or default empty address space is produced on invalid ownership.
    return MachineResult[Memory](status: MachineError.InvalidOwner)
  if uint32(first) > uint32(past) or uint32(past) > 0x100000'u32:
    # Validate the exclusive endpoint before subtraction and native-int conversion.
    return MachineResult[Memory](status: MachineError.InvalidRange)
  let start = lowerBound(data, uint32(first))
  let stop = lowerBound(data, uint32(past))
  let added = uint64(uint32(past)-uint32(first)) - uint64(stop-start)
  let total = uint64(data.pages.len) + added
  if total > uint64(uint32(data.limit)) or total > uint64(high(int) div sizeof(PageData)):
    # Count inaccessible retained pages too; only truly absent ordinals require new slots.
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  var changed = added != 0
  for i in start..<stop:
    # Permission-only changes still need a successor, even when no page is added.
    if data.pages[i].image.access != PageAccess.ReadWrite:
      changed = true
  if not changed:
    # Empty and already-writable intervals retain the original immutable owner without allocation.
    return MachineResult[Memory](status: MachineError.None, completed: memory)
  var pages = newSeqOfCap[PageData](int(total))
  for i in 0..<start:
    pages.add(data.pages[i]) # Retain the untouched prefix, including permissions and nonzero bytes.
  var at = start
  var ordinal = uint32(first)
  while ordinal < uint32(past):
    # Merge the validated interval with the sorted retained vector exactly once.
    if at < stop and uint32(data.pages[at].image.index) == ordinal:
      if data.pages[at].image.access == PageAccess.ReadWrite:
        pages.add(data.pages[at]) # Already-writable page storage stays shared and immutable.
      else:
        var page = data.pages[at].image # Retain inaccessible/read-only bytes when changing access.
        page.access = PageAccess.ReadWrite
        pages.add(PageData(image: page))
      inc at
    else:
      # An absent page has implicit zero storage; materialization must preserve those bytes.
      pages.add(PageData(image: PageImage(index: PageIndex(ordinal), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))))
    inc ordinal
  for i in stop..<data.pages.len:
    pages.add(data.pages[i]) # The exclusive endpoint and entire suffix remain untouched.
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pages, limit: data.limit)))

proc withPageRange*(memory: Memory, first, past: PageIndex, access: PageAccess,
    content: PageContent): MachineResult[Memory] =
  ## Atomically clear or remap [first,past), retaining all outside bytes and the original page budget.
  ## This trusted environment operation imposes no host geometry/gas/previous-access rules itself.
  let data = memory.data
  if data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  if uint32(first) > uint32(past) or uint32(past) > 0x100000'u32:
    return MachineResult[Memory](status: MachineError.InvalidRange) # Validate both ordinals before subtraction or lookup.
  if uint32(first) == uint32(past):
    return MachineResult[Memory](status: MachineError.None,
        completed: memory) # Empty intervals preserve the exact owner.
  let start = lowerBound(data, uint32(first))
  let stop = lowerBound(data, uint32(past))
  let dropped = access == PageAccess.Inaccessible and content == PageContent.Zeroed
  let interval = if dropped: 0'u64 else: uint64(uint32(past)-uint32(first))
  let total = uint64(data.pages.len-(stop-start))+interval
  if total > uint64(uint32(data.limit)) or total > uint64(high(int) div sizeof(PageData)):
    return MachineResult[Memory](status: MachineError.LimitExceeded) # All prospective pages count before any private allocation.
  var pages = newSeqOfCap[PageData](int(total))
  for index in 0..<start: pages.add(data.pages[index]) # Preserve immutable outside prefix owners.
  if not dropped:
    var ordinal = uint32(first)
    var at = start
    while ordinal < uint32(past):
      var image = PageImage(index: PageIndex(ordinal), access: access,
        bytes: default(array[4096, byte]))
      if at < stop and uint32(data.pages[at].image.index) == ordinal:
        if content == PageContent.Preserved:
          image.bytes = data.pages[at].image.bytes # Read-only/inaccessible retained bytes survive trusted remapping.
        inc at # Each present old page is consumed exactly once in the ordered interval.
      pages.add(PageData(image: image))
      inc ordinal # The validated exclusive endpoint bounds every ordinal below 2^20.
  for index in stop..<data.pages.len: pages.add(data.pages[
      index]) # Dropped zero/inaccessible pages become implicit sparse zeros.
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

proc load*(memory: Memory, address: MemoryAddress, width: AccessWidth): MachineResult[
    RegisterValue] =
  ## Load a little-endian unsigned scalar; sign extension belongs to the eventual instruction executor.
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

proc store*(memory: Memory, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[Memory] =
  ## Store the low width bytes atomically into a new owner; no source snapshot can change on failure.
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

# Validate a natural host range and all permissions before copying any payload or page storage.
# Fault is a diagnostic page here; the concrete host function decides its guest panic/result mapping.
proc inspectRange(memory: Memory, address: MemoryAddress, length: MemoryLength,
    limit: MemoryByteLimit, writing: bool): MachineResult[bool] =
  if memory.data == nil:
    # Empty ranges still require a genuine immutable owner.
    return MachineResult[bool](status: MachineError.InvalidOwner)
  let size = uint64(length)
  if size == 0:
    # The empty natural interval is accessible for every pointer, even UINT64_MAX.
    return MachineResult[bool](status: MachineError.None, completed: true)
  let start = uint64(address)
  if start >= 0x100000000'u64 or size > 0x100000000'u64 - start:
    # Host ranges never wrap or silently discard high pointer bits.
    return MachineResult[bool](status: MachineError.InvalidRange)
  if size > uint64(limit) or size > uint64(high(int)):
    # Bound permission scanning and later allocation before narrowing to a native sequence index.
    return MachineResult[bool](status: MachineError.LimitExceeded)
  let lastPage = (start + size - 1) div 4096
  var page = start div 4096
  let data = memory.data
  while page <= lastPage:
    # Page permissions suffice for every byte in this nonwrapping interval, including low memory.
    let at = lowerBound(data, uint32(page))
    if at == data.pages.len or uint32(data.pages[at].image.index) != uint32(page):
      # Absent sparse pages are inaccessible; report the first failing physical page in range order.
      return MachineResult[bool](status: MachineError.Fault, failedPage: PageAddress(uint32(page * 4096)))
    let access = data.pages[at].image.access
    if access == PageAccess.Inaccessible or (writing and access != PageAccess.ReadWrite):
      # Retained inaccessible bytes are not readable; read-only pages cannot receive host writes.
      return MachineResult[bool](status: MachineError.Fault, failedPage: PageAddress(uint32(page * 4096)))
    inc page
  MachineResult[bool](status: MachineError.None, completed: true)

proc readableRange*(memory: Memory, address: MemoryAddress, length: MemoryLength): MachineResult[bool] =
  ## Inspect a complete natural readable interval without allocating payload bytes or applying a caller copy budget.
  ## The physical 4-GiB domain bounds scanning; empty intervals ignore the pointer but still validate the owner.
  inspectRange(memory, address, length, MemoryByteLimit(0x100000000'u64), false)

proc writableRange*(memory: Memory, address: MemoryAddress, length: MemoryLength): MachineResult[bool] =
  ## Inspect a complete natural writable interval without mutation, preserving the first physical fault reason.
  ## Host dispatchers can establish permission precedence before ID lookup and independent local copying policy.
  inspectRange(memory, address, length, MemoryByteLimit(0x100000000'u64), true)

proc readBytes*(memory: Memory, address: MemoryAddress, length: MemoryLength,
    limit: MemoryByteLimit): MachineResult[seq[byte]] =
  ## Copy a complete readable host range into independent bytes; failure never exposes a readable prefix.
  let checked = inspectRange(memory, address, length, limit, false)
  if checked.error != MachineError.None:
    # Preserve the exact local reason or first inaccessible page without publishing partial bytes.
    return failure[seq[byte], bool](checked)
  if memory.data == nil:
    # Reestablish the validated non-nil owner for the compiler's local flow analysis.
    return MachineResult[seq[byte]](status: MachineError.InvalidOwner)
  let data = memory.data
  let size = int(uint64(length))
  var bytes = newSeq[byte](size)
  var copied = 0
  while copied < size:
    # The preflight proved all addresses and native index conversions before allocation.
    let physical = uint64(address) + uint64(copied)
    let at = lowerBound(data, uint32(physical div 4096))
    let offset = int(physical mod 4096)
    let count = min(size - copied, 4096 - offset)
    for i in 0..<count:
      # Copy only the requested portion of each page; no mutable page reference escapes.
      bytes[copied + i] = data.pages[at].image.bytes[offset + i]
    copied += count
  MachineResult[seq[byte]](status: MachineError.None, completed: bytes)

proc writeBytes*(memory: Memory, address: MemoryAddress, input: openArray[byte],
    limit: MemoryByteLimit): MachineResult[Memory] =
  ## Atomically copy borrowed input into a new memory snapshot; unchanged pages remain shared immutable.
  ## Input is borrowed only during this call. Failed writes never alter or expose a partial successor.
  let checked = inspectRange(memory, address, MemoryLength(uint64(input.len)), limit, true)
  if checked.error != MachineError.None:
    # Full permission and policy checks precede every cloned page and reference-vector allocation.
    return failure[Memory, bool](checked)
  if input.len == 0:
    # Empty writes retain the immutable source without allocating a redundant snapshot.
    return MachineResult[Memory](status: MachineError.None, completed: memory)
  if memory.data == nil:
    # The compiler requires this explicit non-nil selection after the helper's validation.
    return MachineResult[Memory](status: MachineError.InvalidOwner)
  let data = memory.data
  var pages = newSeqOfCap[PageData](data.pages.len)
  for page in data.pages:
    # Share all old page owners initially; each touched page is cloned exactly once below.
    pages.add(page)
  var copied = 0
  while copied < input.len:
    # Nonwrapping contiguous ranges visit each affected page exactly once.
    let physical = uint64(address) + uint64(copied)
    let at = lowerBound(data, uint32(physical div 4096))
    let offset = int(physical mod 4096)
    let count = min(input.len - copied, 4096 - offset)
    pages[at] = PageData(image: data.pages[at].image)
    for i in 0..<count:
      # Mutations target only the private clone; untouched bytes and permissions are preserved.
      pages[at].image.bytes[offset + i] = input[copied + i]
    copied += count
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pages, limit: data.limit)))

proc captureMachine*(program: Program, memory: Memory, info: MachineInfo): MachineResult[Machine] =
  ## Capture a validated entry location and copied CPU values; this is not standard JAM initialization.
  # Empty/default memory must be distinguished from a valid all-inaccessible memory snapshot.
  if memory.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  if uint64(info.gasDeficit) != 0:
    # Negative balances are terminal state and cannot be captured as executable guest input.
    return MachineResult[Machine](status: MachineError.InvalidGasState)
  # Reuse the base PR's instruction-boundary validation without re-decoding or copying its program.
  if instruction(program, info.pc).error != ProgramError.None:
    return MachineResult[Machine](status: MachineError.InvalidProgram)
  MachineResult[Machine](status: MachineError.None,
    completed: Machine(data: MachineData(program: program, memory: memory, info: info)))

proc captureTerminalMachine*(program: Program, memory: Memory,
    info: MachineInfo): MachineResult[Machine] =
  ## Capture a terminal execution snapshot whose PC need not identify an executable instruction.
  ## This trusted boundary preserves Psi_1 trap PCs beyond the code; it does not validate an exit reason.
  ## Program/memory are immutable owned children; no caller-owned mutable state is retained.
  # Even terminal snapshots require genuine program and memory owners.
  if memory.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  if uint64(info.gasDeficit) > 0x8000000000000000'u64 or
      (uint64(info.gasDeficit) != 0 and uint64(info.gas) != 0):
    # Canonical balances never carry simultaneous credit/debt or exceed the signed negative domain.
    return MachineResult[Machine](status: MachineError.InvalidGasState)
  if codeLength(program).error != ProgramError.None:
    return MachineResult[Machine](status: MachineError.InvalidProgram)
  MachineResult[Machine](status: MachineError.None,
    completed: Machine(data: MachineData(program: program, memory: memory, info: info)))

proc machineInfo*(machine: Machine): MachineResult[MachineInfo] =
  ## Copy all CPU values; changes to this returned value cannot affect its source machine.
  # Default handles do not imply zero registers or successful execution.
  if machine.data == nil: return MachineResult[MachineInfo](status: MachineError.InvalidOwner)
  MachineResult[MachineInfo](status: MachineError.None, completed: machine.data.info)

proc memoryOf*(machine: Machine): MachineResult[Memory] =
  ## Retain the immutable memory handle for inspection or environment-driven page recovery.
  # Ownership must be established before extracting a child handle.
  if machine.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  MachineResult[Memory](status: MachineError.None, completed: machine.data.memory)

proc withMemory*(machine: Machine, memory: Memory): MachineResult[Machine] =
  ## Replace only the memory owner after an environment repair; CPU state/program remain unchanged.
  # Neither parent nor replacement may be an uninitialized owner.
  if machine.data == nil or memory.data == nil:
    return MachineResult[Machine](status: MachineError.InvalidOwner)
  MachineResult[Machine](status: MachineError.None, completed: Machine(data: MachineData(
    program: machine.data.program, memory: memory, info: machine.data.info)))

proc withRegister*(machine: Machine, index: RegisterIndex,
    value: RegisterValue): MachineResult[Machine] =
  ## Update one copied register without executing an instruction or charging gas.
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

proc store*(machine: Machine, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[Machine] =
  ## A successful memory update replaces only memory; every CPU field survives unchanged.
  # A default machine cannot manufacture a successful update from default memory.
  if machine.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  let data = machine.data
  let updated = store(data.memory, address, width, value)
  # Forward the complete reason, including a fault address, without publishing a partial machine.
  if updated.error != MachineError.None: return failure[Machine, Memory](updated)
  withMemory(machine, updated.value)

proc programOf*(machine: Machine): MachineResult[Program] =
  ## Retain the immutable program belonging to this exact snapshot; never accept a separate substitute.
  # Default handles have no program identity to expose.
  if machine.data == nil: return MachineResult[Program](status: MachineError.InvalidOwner)
  MachineResult[Program](status: MachineError.None, completed: machine.data.program)
