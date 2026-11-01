# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 machine snapshots and sparse memory; see spec/pvm-machine.md. Published owners are
## immutable, acyclic ARC graphs. Updates return independent snapshots.
##
## Exposes immutable Memory/Machine snapshots, page capture/replacement, checked scalar
## load/store, bounded host readBytes/writeBytes, allocation-free readableRange/writableRange,
## programOf/memoryOf child access, copied state
## updates, writable-page range counting/mapping, atomic zero/remap/free ranges and terminal-state capture.

import std/assertions
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
  MachineGas* = distinct uint64 ## Complete unsigned gas balance under the unreleased Gray Paper.
  GasDeficit* = distinct uint64 ## Reserved-zero compatibility field; signed host gas was removed by GP PR533.
  RegisterFile* = array[13, RegisterValue] ## Every machine snapshot contains exactly thirteen copied register values.
  PageAccess* {.pure.} = enum ## Writable pages are also readable; inaccessible pages may retain bytes for later remapping.
    Inaccessible, ReadOnly, ReadWrite
  PageContent* {.pure.} = enum ## Trusted page-range updates explicitly choose retained bytes or all-zero replacement.
    Preserved, Zeroed
  PageImage* = object ## Caller-owned page input is copied and never retained by reference.
    index*: PageIndex
    access*: PageAccess
    bytes*: array[4096, byte]
  MemoryPageSlot* = distinct uint32 ## Position within the supplied immutable owner's sorted mapping, separate from a physical page ordinal.
  PageDescription* = object ## Copied mapping metadata grants no mutable page storage or guest access permission.
    index*: PageIndex
    access*: PageAccess
  MachineError* {.pure.} = enum ## Local API failures are distinct from guest panic/fault, with retained historical error identifiers.
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
  # Fixed chunks are immutable after publication; a scalar clones at most two small payloads.
  PageChunk = ref object
    bytes: array[512, byte]
  # A page header owns exactly eight initialized chunks; permissions and bytes remain snapshot-local.
  PageData = ref object
    index: PageIndex
    access: PageAccess
    chunks: array[8, PageChunk]
  # Immutable directory blocks share untouched page-reference groups between snapshots.
  PageBlock = ref object
    entries: seq[PageData] # Each immutable block has at most 64 initialized page references.
  PageDirectory = object
    len: int
    blocks: seq[PageBlock]
  # Sorted sparse page references avoid allocating the entire 4 GiB guest address space.
  MemoryData = ref object
    pages: PageDirectory
    limit: PageLimit
  Memory* = object ## A default handle is invalid; captureMemory([], ...) creates valid empty memory.
    data: nil MemoryData
  ScalarMemoryWriter* = ref object ## Mutable scalar-write identity; copied handles share progress, while snapshotMemory publishes immutable epochs.
    base: Memory
    pages: seq[PageData]
    dirty: seq[byte]
    active: bool
    readPage: nil PageData # One completely preflighted readable page, retired before COW replacement.
    readTag: uint64
    writePage: nil PageData # One private current-epoch page header; untouched chunks remain immutable.
    writeTag: uint64
    spareWritePage: nil PageData # Second private writable page; hits retain owners without shuffling references.
    spareWriteTag: uint64
    spareWriteSlot: int
    writeSlot: int        # Exact stable sorted slot admitted with this retained page owner.
    recent: array[2, int] # Fixed page slots retain no page/chunk owner and never imply permissions.
    pageSlots: array[64, uint32] # Miss-only positive sorted-slot hints retain no page owner or permission authority.
    writePrivate, spareWritePrivate: byte # Underapproximated private-chunk facts travel with their exact retained epoch windows.
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

func checkedPageBlock(pages: PageDirectory, index: int): int {.inline.} =
  ## Every lookup retains the original complete sorted-slot bound, including the last partial block.
  assert index >= 0 and index < pages.len
  index div 64

template `[]`(pages: PageDirectory, index: int): untyped =
  ## Expand a borrowed indexed location; no owning PageData result is created by an accessor call.
  pages.blocks[checkedPageBlock(pages, index)].entries[index and 63]

proc pageDirectory(pages: sink seq[PageData]): PageDirectory =
  ## Transfer an admitted sorted vector into immutable blocks without another per-page retain/release pass.
  var owned = move(pages)
  result = PageDirectory(len: owned.len, blocks: @[])
  var first = 0
  while first < owned.len:
    # The final block contains only its initialized references.
    let count = min(64, owned.len-first)
    var group = PageBlock(entries: newSeqOfCap[PageData](count))
    for offset in 0..<count:
      # Moving empties the old vector slot; its destructor cannot release the transferred page again.
      group.entries.add(move(owned[first+offset]))
    result.blocks.add(move(group))
    first += count

proc replacedDirectory(pages: PageDirectory, slots: openArray[int],
    replacements: openArray[PageData]): PageDirectory =
  ## All callers preflight before construction; copy the root and clone each affected block exactly once.
  assert slots.len == replacements.len
  result = PageDirectory(len: pages.len, blocks: newSeqOfCap[PageBlock](pages.blocks.len))
  for index in 0..<pages.blocks.len:
    # Unchanged immutable blocks retain their shared children rather than retaining every page anew.
    result.blocks.add(pages.blocks[index])
  var previous = -1
  var previousGroup = -1
  for index in 0..<slots.len:
    # Strict ascending slots make repeated changes within a block share one fresh private copy.
    let slot = slots[index]
    assert slot >= 0 and slot < pages.len and slot > previous
    let group = slot div 64
    if group != previousGroup:
      # The old block remains immutable through its retained source root.
      var entries = newSeqOfCap[PageData](pages.blocks[group].entries.len)
      for offset in 0..<pages.blocks[group].entries.len:
        # Copy only this block's initialized references; no mutable sequence is shared.
        entries.add(pages.blocks[group].entries[offset])
      let copied = PageBlock(entries: move(entries))
      result.blocks[group] = copied
      previousGroup = group
    result.blocks[group].entries[slot and 63] = replacements[index]
    previous = slot

func error*[T](r: MachineResult[T]): MachineError =
  ## Status inspection cannot retag or forge a result.
  r.status

func value*[T](r: MachineResult[T]): T {.inline, requires: r.status == MachineError.None.} =
  ## A successful result alone grants access to its copied payload.
  r.completed

proc takeValue*[T](r: var MachineResult[T]): T {.inline, requires: r.status == MachineError.None.} =
  ## Transfer one successful owned payload without copying; consumed results no longer carry success authority.
  result = move(r.completed)
  r = MachineResult[T](status: MachineError.Uninitialized)

func faultPage*[T](r: MachineResult[T]): PageAddress {.inline, requires: r.status ==
    MachineError.Fault.} =
  ## A page address is meaningful only for a guest Fault, never for API failures or panic.
  r.failedPage

func failure[T, U](r: MachineResult[U]): MachineResult[T] {.requires: r.status !=
    MachineError.None.} =
  ## Propagate only a failure reason across payload types without leaking partial success state.
  # Fault is the sole failure with an associated reason parameter.
  if r.status == MachineError.Fault:
    return MachineResult[T](status: MachineError.Fault, failedPage: r.failedPage)
  MachineResult[T](status: r.status)

proc chunkFromImage(image: PageImage, first: int): PageChunk {.requires:
    first >= 0 and first <= 3584.} =
  ## Copy one complete proven span into fresh private storage; no caller-owned backing address survives capture.
  result = PageChunk(bytes: default(array[512, byte]))
  copyMem(addr result.bytes[0], unsafeAddr image.bytes[first], 512)

proc pageFromImage(image: PageImage): PageData =
  ## Construct all eight non-nil chunk owners before publishing an immutable page header.
  PageData(index: image.index, access: image.access, chunks: [
    chunkFromImage(image, 0), chunkFromImage(image, 512), chunkFromImage(image, 1024),
    chunkFromImage(image, 1536), chunkFromImage(image, 2048), chunkFromImage(image, 2560),
    chunkFromImage(image, 3072), chunkFromImage(image, 3584)])

proc sharedZeroChunk(seed: var nil PageChunk): PageChunk =
  ## Lazily retain one immutable known-zero payload within this mapping operation; no process-global pool exists.
  let current = seed
  if current != nil:
    return current # Permission-only changes need no seed, and later new pages share this immutable payload.
  let fresh = PageChunk(bytes: default(array[512, byte]))
  seed = fresh
  fresh

proc zeroPage(index: PageIndex, access: PageAccess, seed: var nil PageChunk): PageData =
  ## Only absent or explicitly cleared pages reach this helper; every later writer still clones touched chunks first.
  let chunk = sharedZeroChunk(seed)
  PageData(index: index, access: access, chunks: [chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk])

func pageByte(page: PageData, offset: int): byte {.inline.} =
  ## Read one proven page offset without returning a mutable chunk or retaining a transient reference.
  page.chunks[offset div 512].bytes[offset mod 512]

func pageScalar(page: PageData, offset, count: int): uint64 {.inline,
    requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 8 and count <=
        4096-offset.} =
  ## Copy a proven scalar span from one immutable chunk into a private initialized word; no borrowed address escapes.
  result = 0
  if count == 1: return uint64(pageByte(page, offset))
  let chunk = offset div 512
  let within = offset mod 512
  if within <= 512-count:
    # Disjoint stack and immutable heap storage permit an unaligned-safe copy only after proving the entire source extent.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      case count
      of 2:
        # Fixed admitted widths lower to unaligned-safe native loads without a variable copy call.
        copyMem(addr result, unsafeAddr page.chunks[chunk].bytes[within], 2)
      of 4:
        # Copy the complete half-register span after the same permission and chunk preflight.
        copyMem(addr result, unsafeAddr page.chunks[chunk].bytes[within], 4)
      of 8:
        # A full register still reads exactly eight bytes, including unaligned offsets.
        copyMem(addr result, unsafeAddr page.chunks[chunk].bytes[within], 8)
      else:
        # Page-fragment widths retain the original bounded byte-count copy.
        copyMem(addr result, unsafeAddr page.chunks[chunk].bytes[within], count)
      return # Little-endian hosts now hold the exact zero-extended guest word.
  for index in 0..<count:
    # Big-endian hosts and chunk-crossing spans retain the portable byte-wise equation.
    result = result or (uint64(pageByte(page, offset+index)) shl (8*index))

proc imageFromPage(page: PageData): PageImage =
  ## Materialize the public copied image; chunk sharing never escapes through observation.
  result = PageImage(index: page.index, access: page.access, bytes: default(array[4096, byte]))
  for slot in 0..<8:
    # Each immutable chunk supplies exactly512 bytes to its disjoint fixed-array span in the fresh copied image.
    copyMem(addr result.bytes[slot*512], unsafeAddr page.chunks[slot].bytes[0], 512)

proc pageWithAccess(page: PageData, access: PageAccess): PageData =
  ## Permission-only successors share immutable chunks and cannot change predecessor access or bytes.
  PageData(index: page.index, access: access, chunks: page.chunks)

proc writablePageClone(page: PageData, offset, count: int): PageData =
  ## Callers preflight a nonempty interval within this page; clone its header and only touched chunks before mutation.
  result = pageWithAccess(page, page.access)
  let first = offset div 512
  let last = (offset+count-1) div 512
  for slot in first..last:
    result.chunks[slot] = PageChunk(bytes: page.chunks[
        slot].bytes) # Untouched payloads stay immutable and shared.

proc setPageByte(page: PageData, offset: int, value: byte) {.inline.} =
  ## Only private writable clones reach this helper, and their touched chunk was copied before the first write.
  page.chunks[offset div 512].bytes[offset mod 512] = value

proc setPageScalar(page: PageData, offset, count: int, value: uint64) {.inline,
    requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 8 and count <=
        4096-offset.} =
  ## Callers exclusively own every touched chunk after clone/prepare; no immutable snapshot storage is modified.
  if count == 1:
    setPageByte(page, offset, byte(value and 255))
    return
  let chunk = offset div 512
  let within = offset mod 512
  if within <= 512-count:
    # Copy only a complete admitted span from a disjoint initialized stack word into the private chunk.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      var word = value
      case count
      of 2:
        # Fixed admitted widths permit native unaligned-safe stores after private-chunk preparation.
        copyMem(addr page.chunks[chunk].bytes[within], addr word, 2)
      of 4:
        # Only the low four little-endian bytes replace this proven private extent.
        copyMem(addr page.chunks[chunk].bytes[within], addr word, 4)
      of 8:
        # The full register replaces exactly the admitted eight-byte span.
        copyMem(addr page.chunks[chunk].bytes[within], addr word, 8)
      else:
        # Cross-page fragments retain their original exact-width copy.
        copyMem(addr page.chunks[chunk].bytes[within], addr word, count)
      return
  for index in 0..<count:
    # Big-endian and chunk-crossing writes retain byte-wise little-endian semantics.
    setPageByte(page, offset+index, byte((value shr (8*index)) and 255))

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
  for i in 0..<pages.len: owned.add(pageFromImage(pages[i]))
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pageDirectory(move(owned)), limit: limit)))

func lowerBound(data: MemoryData, index: uint32): int =
  ## Locate the first stored page whose index is at least the requested ordinal.
  var first = 0
  var last = data.pages.len
  # Difference-based midpoint arithmetic avoids overflowing endpoint sums.
  while first < last:
    let middle = first + (last - first) div 2
    # Discard the lower half only when its page precedes the requested one.
    if uint32(data.pages[middle].index) < index: first = middle + 1
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
  if at < data.pages.len and uint32(data.pages[at].index) == uint32(index):
    return MachineResult[PageImage](status: MachineError.None, completed: imageFromPage(data.pages[at]))
  MachineResult[PageImage](status: MachineError.None, completed: PageImage(index: index,
    access: PageAccess.Inaccessible, bytes: default(array[4096, byte])))

proc changedMemoryPages*(before, after: Memory): MachineResult[seq[PageImage]] =
  ## Shared immutable directory blocks prove all their page identities and metadata equal at once.
  let left = before.data
  let right = after.data
  if left == nil or right == nil: return MachineResult[seq[PageImage]](
      status: MachineError.InvalidOwner)
  if left == right: return MachineResult[seq[PageImage]](status: MachineError.None, completed: @[])
  if left.pages.len != right.pages.len:
    return MachineResult[seq[PageImage]](status: MachineError.InvalidRange)
  for group in 0..<left.pages.blocks.len:
    # Equal lengths have the same fixed block partition; shared blocks require no page-by-page walk.
    if left.pages.blocks[group] == right.pages.blocks[group]: continue
    let first = group*64
    let past = min(first+64, left.pages.len)
    for index in first..<past:
      # Different page owners can still retain equal mappings; complete validation precedes delta allocation.
      if left.pages[index] == right.pages[index]: continue
      if left.pages[index].index != right.pages[index].index or
          left.pages[index].access != right.pages[index].access:
        return MachineResult[seq[PageImage]](status: MachineError.InvalidRange)
  var changed: seq[PageImage] = @[]
  for group in 0..<left.pages.blocks.len:
    # Only changed blocks can contain changed page owners, and ascending slots keep the output sorted.
    if left.pages.blocks[group] == right.pages.blocks[group]: continue
    let first = group*64
    let past = min(first+64, left.pages.len)
    for index in first..<past:
      if left.pages[index] != right.pages[index]: changed.add(imageFromPage(right.pages[index]))
  MachineResult[seq[PageImage]](status: MachineError.None, completed: changed)

proc changedMemoryPageSlots*(before, after: Memory): MachineResult[seq[MemoryPageSlot]] =
  ## Validate the complete retained map, then return sorted positions whose immutable page owners differ.
  ## Shared directory blocks need no scan; callers copy bytes through the validated after owner by slot.
  let left = before.data
  let right = after.data
  if left == nil or right == nil: return MachineResult[seq[MemoryPageSlot]](
      status: MachineError.InvalidOwner)
  if left == right: return MachineResult[seq[MemoryPageSlot]](
      status: MachineError.None, completed: @[])
  if left.pages.len != right.pages.len:
    return MachineResult[seq[MemoryPageSlot]](status: MachineError.InvalidRange)
  for group in 0..<left.pages.blocks.len:
    # Equal block owners certify every identity and permission in that group.
    if left.pages.blocks[group] == right.pages.blocks[group]: continue
    let first = group*64
    let past = min(first+64, left.pages.len)
    for slot in first..<past:
      # Refuse every map difference before allocating or returning any changed positions.
      if left.pages[slot] == right.pages[slot]: continue
      if left.pages[slot].index != right.pages[slot].index or
          left.pages[slot].access != right.pages[slot].access:
        return MachineResult[seq[MemoryPageSlot]](status: MachineError.InvalidRange)
  var changed: seq[MemoryPageSlot] = @[]
  for group in 0..<left.pages.blocks.len:
    # Ascending groups and positions produce sorted slots without sorting or copying page payloads.
    if left.pages.blocks[group] == right.pages.blocks[group]: continue
    let first = group*64
    let past = min(first+64, left.pages.len)
    for slot in first..<past:
      if left.pages[slot] != right.pages[slot]: changed.add(MemoryPageSlot(uint32(slot)))
  MachineResult[seq[MemoryPageSlot]](status: MachineError.None, completed: changed)

func memoryPageCount*(memory: Memory): MachineResult[PageCount] =
  ## Inspect a genuine owner's mapping size without copying page payloads, for local admission before host deltas.
  let data = memory.data
  if data == nil: return MachineResult[PageCount](status: MachineError.InvalidOwner)
  MachineResult[PageCount](status: MachineError.None, completed: PageCount(uint32(data.pages.len)))

proc memoryImages*(memory: Memory): MachineResult[seq[PageImage]] =
  ## Copy every retained page for a genuine mapping/permission replacement; no private reference escapes.
  let data = memory.data
  if data == nil: return MachineResult[seq[PageImage]](status: MachineError.InvalidOwner)
  var images = newSeqOfCap[PageImage](data.pages.len)
  for i in 0..<data.pages.len: images.add(imageFromPage(data.pages[i]))
  MachineResult[seq[PageImage]](status: MachineError.None, completed: images)

proc memoryLayout*(memory: Memory): MachineResult[seq[PageDescription]] =
  ## Copy sorted mapping metadata without extracting page bytes; a default owner refuses before allocation.
  let data = memory.data
  if data == nil:
    return MachineResult[seq[PageDescription]](status: MachineError.InvalidOwner)
  var pages = newSeq[PageDescription](data.pages.len)
  for slot in 0..<pages.len:
    # The immutable owner's validated order and permissions remain authoritative for every copied description.
    pages[slot] = PageDescription(index: data.pages[slot].index, access: data.pages[slot].access)
  MachineResult[seq[PageDescription]](status: MachineError.None, completed: pages)

proc copyMemoryPage*(memory: Memory, slot: MemoryPageSlot,
    output: var openArray[byte]): MachineResult[PageDescription] =
  ## Copy one captured page directly into caller-owned storage, including retained inaccessible bytes.
  ## Owner, position and exact output length are checked before writing; failures leave output untouched.
  let data = memory.data
  if data == nil:
    return MachineResult[PageDescription](status: MachineError.InvalidOwner)
  if uint64(slot) >= uint64(data.pages.len) or output.len != 4096:
    return MachineResult[PageDescription](status: MachineError.InvalidRange)
  let page {.cursor.} = data.pages[int(uint32(slot))]
  for chunk in 0..<8:
    # Each fixed512-byte immutable chunk copies into a disjoint proven portion of the complete output page.
    copyMem(addr output[chunk*512], unsafeAddr page.chunks[chunk].bytes[0], 512)
  MachineResult[PageDescription](status: MachineError.None,
    completed: PageDescription(index: page.index, access: page.access))

proc pageIndices*(memory: Memory): MachineResult[seq[PageIndex]] =
  ## Copy only retained sorted page identities; sparse holes and snapshot storage remain private.
  let data = memory.data
  if data == nil: return MachineResult[seq[PageIndex]](status: MachineError.InvalidOwner)
  var indices = newSeq[PageIndex](data.pages.len)
  for index in 0..<data.pages.len:
    indices[index] = data.pages[index].index # Copying ordinals grants no mutable page access.
  MachineResult[seq[PageIndex]](status: MachineError.None, completed: indices)

proc samePage*(left, right: Memory, index: PageIndex): bool =
  ## Identity comparison avoids copying unchanged immutable pages at a foreign continuation boundary.
  let a = left.data
  let b = right.data
  if a == nil or b == nil or uint32(index) >= 0x100000'u32: return false
  let ai = lowerBound(a, uint32(index))
  let bi = lowerBound(b, uint32(index))
  let ap = ai < a.pages.len and uint32(a.pages[ai].index) == uint32(index)
  let bp = bi < b.pages.len and uint32(b.pages[bi].index) == uint32(index)
  if not ap or not bp: return not ap and not bp # Two absent pages have the same inaccessible content.
  a.pages[ai] == b.pages[bi]

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
  let replacing = at < data.pages.len and uint32(data.pages[at].index) == uint32(page.index)
  # Replacing a page at the ceiling is permitted; inserting another is not.
  if not replacing and uint64(data.pages.len) >= uint64(uint32(data.limit)):
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  var pages = newSeqOfCap[PageData](data.pages.len + int(not replacing))
  # Reuse immutable page references outside the one replacement/insertion slot.
  for i in 0..<at: pages.add(data.pages[i])
  pages.add(pageFromImage(page))
  # Insertion shifts the suffix; replacement leaves its positions unchanged.
  for i in at + int(replacing)..<data.pages.len:
    pages.add(data.pages[i])
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pageDirectory(move(pages)), limit: data.limit)))

proc withReplacedPages*(memory: Memory, replacements: openArray[PageImage]): MachineResult[Memory] =
  ## Atomically replace sorted existing pages, sharing untouched directory blocks and snapshot chunks.
  let data = memory.data
  if data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  for index in 0..<replacements.len:
    # Preserve physical-index and strict-order refusal precedence before matching any source page.
    if uint32(replacements[index].index) >= 0x100000'u32:
      return MachineResult[Memory](status: MachineError.InvalidPage)
    if index > 0 and uint32(replacements[index-1].index) >= uint32(replacements[index].index):
      return MachineResult[Memory](status: MachineError.UnsortedPages)
  let sparse = replacements.len < data.pages.len div 8
  var cursor = 0
  for index in 0..<replacements.len:
    # Sparse far-apart updates use bounded searches; dense replacements retain the linear merge.
    if sparse:
      cursor = lowerBound(data, uint32(replacements[index].index))
    else:
      while cursor < data.pages.len and uint32(data.pages[cursor].index) < uint32(replacements[index].index):
        inc cursor
    if cursor >= data.pages.len or data.pages[cursor].index != replacements[index].index or
        data.pages[cursor].access != replacements[index].access:
      return MachineResult[Memory](status: MachineError.InvalidRange)
    inc cursor
  if replacements.len == 0:
    # An empty observation retains the exact original owner and policy without allocation.
    return MachineResult[Memory](status: MachineError.None, completed: memory)
  var slots = newSeqOfCap[int](replacements.len)
  var changed = newSeqOfCap[PageData](replacements.len)
  cursor = 0
  for index in 0..<replacements.len:
    # Every input has passed; collect exact slots and new immutable byte owners only now.
    if sparse:
      cursor = lowerBound(data, uint32(replacements[index].index))
    else:
      while uint32(data.pages[cursor].index) < uint32(replacements[index].index): inc cursor
    slots.add(cursor)
    changed.add(pageFromImage(replacements[index]))
    inc cursor
  var directory = replacedDirectory(data.pages, slots, changed)
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: move(directory), limit: data.limit)))

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
    if data.pages[i].access == PageAccess.ReadWrite:
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
    if data.pages[i].access != PageAccess.ReadWrite:
      changed = true
  if not changed:
    # Empty and already-writable intervals retain the original immutable owner without allocation.
    return MachineResult[Memory](status: MachineError.None, completed: memory)
  var pages = newSeqOfCap[PageData](int(total))
  for i in 0..<start:
    pages.add(data.pages[i]) # Retain the untouched prefix, including permissions and nonzero bytes.
  var zero: nil PageChunk = nil # Keep a lazy payload only until this operation has published all immutable children.
  var at = start
  var ordinal = uint32(first)
  while ordinal < uint32(past):
    # Merge the validated interval with the sorted retained vector exactly once.
    if at < stop and uint32(data.pages[at].index) == ordinal:
      if data.pages[at].access == PageAccess.ReadWrite:
        pages.add(data.pages[at]) # Already-writable page storage stays shared and immutable.
      else:
        pages.add(pageWithAccess(data.pages[at], PageAccess.ReadWrite)) # Retain all immutable chunks when changing only access.
      inc at
    else:
      # An absent page has implicit zero storage; materialization must preserve those bytes.
      pages.add(zeroPage(PageIndex(ordinal), PageAccess.ReadWrite, zero))
    inc ordinal
  for i in stop..<data.pages.len:
    pages.add(data.pages[i]) # The exclusive endpoint and entire suffix remain untouched.
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pageDirectory(move(pages)), limit: data.limit)))

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
    var zero: nil PageChunk = nil # Dropping zero/inaccessible storage never allocates a replacement payload.
    var ordinal = uint32(first)
    var at = start
    while ordinal < uint32(past):
      if at < stop and uint32(data.pages[at].index) == ordinal and content == PageContent.Preserved:
        pages.add(pageWithAccess(data.pages[at], access)) # Retain inaccessible/read-only bytes without copying payloads.
      else:
        pages.add(zeroPage(PageIndex(ordinal), access,
            zero)) # New headers share only known immutable zero bytes, never an old nonzero payload.
      if at < stop and uint32(data.pages[at].index) == ordinal:
        inc at # Each present old page is consumed exactly once in the ordered interval.
      inc ordinal # The validated exclusive endpoint bounds every ordinal below 2^20.
  for index in stop..<data.pages.len: pages.add(data.pages[
      index]) # Dropped zero/inaccessible pages become implicit sparse zeros.
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: pageDirectory(move(pages)), limit: data.limit)))

type ScalarSpan = object
  ## Private validated slots and byte extents belong only to the immutable memory inspected in this call.
  first, last, offset, firstCount, count: int

proc scalarSlot[Cached: static[bool]](data: MemoryData, page: uint32,
    recent: array[2, int], hints: nil ptr array[64, uint32]): int {.inline.} =
  ## Immutable calls compile without hint probes; writer calls accept only exact bounded physical-page matches.
  when Cached:
    for slot in recent:
      if slot >= 0 and slot < data.pages.len and uint32(data.pages[slot].index) == page:
        return slot
  when Cached:
    if hints != nil:
      # Coordinates are never capabilities: reject empty, displaced and out-of-range slots by exact original page identity.
      let bucket = int((page xor (page shr 8)) and 63'u32)
      let encoded = hints[][bucket]
      if encoded != 0:
        let slot = int(encoded-1)
        if slot >= 0 and slot < data.pages.len and uint32(data.pages[slot].index) == page:
          return slot
  let found = lowerBound(data, page)
  when Cached:
    if hints != nil and found >= 0 and found < data.pages.len and
        uint32(data.pages[found].index) == page and uint64(found) < uint64(high(uint32)):
      # Only actual physical presence is remembered; the caller still checks permissions before byte access.
      let bucket = int((page xor (page shr 8)) and 63'u32)
      hints[][bucket] = uint32(found)+1
  found

proc scalarSpan[Cached, Writing: static[bool]](memory: Memory, address: MemoryAddress,
    width: AccessWidth, recent: array[2, int] = [-1, -1],
    hints: nil ptr array[64, uint32] = nil): MachineResult[ScalarSpan] =
  ## Resolve each touched page once, preserving overflow, protected-memory and presence-before-permission precedence.
  if memory.data == nil: return MachineResult[ScalarSpan](status: MachineError.InvalidOwner)
  if byte(width) notin [1'u8, 2'u8, 4'u8, 8'u8]:
    # Only the four supported widths may enter arithmetic or payload loops.
    return MachineResult[ScalarSpan](status: MachineError.InvalidWidth)
  let data {.cursor.} = memory.data # The caller retains this immutable owner through the complete read-only preflight.
  let start = uint64(address) and 0xffffffff'u64
  if start > uint64(high(uint32)) - uint64(byte(width)):
    # Exclusive-end overflow retains the approved final-page presence rule before permissions.
    let at = scalarSlot[Cached](data, 0xfffff'u32, recent, hints)
    if at < data.pages.len and uint32(data.pages[at].index) == 0xfffff'u32 and
        data.pages[at].access != PageAccess.Inaccessible:
      return MachineResult[ScalarSpan](status: MachineError.Panic)
    return MachineResult[ScalarSpan](status: MachineError.Fault, failedPage: PageAddress(0xfffff000'u32))
  if start < 0x10000'u64:
    # A nonwrapping access starting in the protected prefix panics before any page inspection.
    return MachineResult[ScalarSpan](status: MachineError.Panic)
  let firstPage = uint32(start div 4096)
  let lastPage = uint32((start + uint64(byte(width)) - 1) div 4096)
  let first = scalarSlot[Cached](data, firstPage, recent, hints)
  var firstAccess = PageAccess.Inaccessible
  if first < data.pages.len and uint32(data.pages[first].index) == firstPage:
    firstAccess = data.pages[first].access # Missing sparse slots never grant byte access.
  if firstPage == lastPage:
    # A complete single-page scalar needs one presence/permission decision and no second-page ordering.
    if firstAccess == PageAccess.Inaccessible or (Writing and firstAccess != PageAccess.ReadWrite):
      return MachineResult[ScalarSpan](status: MachineError.Fault,
        failedPage: PageAddress(firstPage * 4096'u32))
    let count = int(byte(width))
    return MachineResult[ScalarSpan](status: MachineError.None, completed: ScalarSpan(
      first: first, last: first, offset: int(start mod 4096), firstCount: count, count: count))
  # The remaining access crosses exactly two pages; complete presence checks still precede write permissions.
  let last = scalarSlot[Cached](data, lastPage, recent, hints)
  var lastAccess = PageAccess.Inaccessible
  if last < data.pages.len and uint32(data.pages[last].index) == lastPage:
    lastAccess = data.pages[last].access
  if firstAccess == PageAccess.Inaccessible:
    return MachineResult[ScalarSpan](status: MachineError.Fault, failedPage: PageAddress(firstPage * 4096'u32))
  if Writing and lastAccess == PageAccess.Inaccessible:
    # A missing second page precedes a read-only first page for cross-page stores (GP-PVM-008).
    return MachineResult[ScalarSpan](status: MachineError.Fault, failedPage: PageAddress(lastPage * 4096'u32))
  if Writing and firstAccess != PageAccess.ReadWrite:
    return MachineResult[ScalarSpan](status: MachineError.Fault, failedPage: PageAddress(firstPage * 4096'u32))
  if lastAccess == PageAccess.Inaccessible or (Writing and lastAccess != PageAccess.ReadWrite):
    return MachineResult[ScalarSpan](status: MachineError.Fault, failedPage: PageAddress(lastPage * 4096'u32))
  let offset = int(start mod 4096)
  let count = int(byte(width))
  MachineResult[ScalarSpan](status: MachineError.None, completed: ScalarSpan(first: first,
    last: last, offset: offset, firstCount: min(count, 4096-offset), count: count))

proc load*(memory: Memory, address: MemoryAddress, width: AccessWidth): MachineResult[
    RegisterValue] =
  ## Load a complete little-endian scalar from preflighted page spans; instruction sign extension remains separate.
  let checked = scalarSpan[false, false](memory, address, width)
  if checked.error != MachineError.None: return failure[RegisterValue, ScalarSpan](checked)
  if memory.data == nil: return MachineResult[RegisterValue](status: MachineError.InvalidOwner)
  let data = memory.data
  let span = checked.value
  var value = pageScalar(data.pages[span.first], span.offset, span.firstCount)
  if span.firstCount < span.count:
    # A remaining suffix proves the prefix is below eight bytes, keeping this shift below64.
    value = value or (pageScalar(data.pages[span.last], 0, span.count-span.firstCount) shl (
        8*span.firstCount))
  MachineResult[RegisterValue](status: MachineError.None, completed: RegisterValue(value))

proc writableScalar*(memory: Memory, address: MemoryAddress, width: AccessWidth): MachineResult[bool] =
  ## Check the exact scalar-store permissions and fault order without allocating or changing memory.
  ## Success carries true; failure preserves store's typed reason and aligned fault page.
  ## Addresses use their low32 bits, including the exclusive-end overflow and protected-prefix rules.
  let checked = scalarSpan[false, true](memory, address, width)
  if checked.error != MachineError.None: return failure[bool, ScalarSpan](checked)
  MachineResult[bool](status: MachineError.None, completed: true)

proc store*(memory: Memory, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[Memory] =
  ## Complete scalar preflight precedes private page/chunk cloning and sparse root publication.
  let checked = scalarSpan[false, true](memory, address, width)
  if checked.error != MachineError.None: return failure[Memory, ScalarSpan](checked)
  if memory.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  let data = memory.data
  let span = checked.value
  var slots = @[span.first]
  var changed = @[writablePageClone(data.pages[span.first], span.offset, span.firstCount)]
  setPageScalar(changed[0], span.offset, span.firstCount, uint64(value))
  if span.firstCount < span.count:
    # Both permissions were validated before either private write; a crossing clones its second page once.
    slots.add(span.last)
    changed.add(writablePageClone(data.pages[span.last], 0, span.count-span.firstCount))
    setPageScalar(changed[1], 0, span.count-span.firstCount, uint64(value) shr (8*span.firstCount))
  var directory = replacedDirectory(data.pages, slots, changed)
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: move(directory), limit: data.limit)))

proc inspectRange(memory: Memory, address: MemoryAddress, length: MemoryLength,
    limit: MemoryByteLimit, writing: bool): MachineResult[bool] =
  ## Validate a natural host range and all permissions before copying any payload or page storage.
  ## Fault is a diagnostic page here; the concrete host function decides its guest panic/result mapping.
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
  var at = lowerBound(data, uint32(page))
  while page <= lastPage:
    # Page permissions suffice for every byte in this nonwrapping interval, including low memory.
    if at == data.pages.len or uint32(data.pages[at].index) != uint32(page):
      # Absent sparse pages are inaccessible; report the first failing physical page in range order.
      return MachineResult[bool](status: MachineError.Fault, failedPage: PageAddress(uint32(page * 4096)))
    let access = data.pages[at].access
    if access == PageAccess.Inaccessible or (writing and access != PageAccess.ReadWrite):
      # Retained inaccessible bytes are not readable; read-only pages cannot receive host writes.
      return MachineResult[bool](status: MachineError.Fault, failedPage: PageAddress(uint32(page * 4096)))
    inc page
    inc at # Strictly ordered stored pages advance with the required contiguous physical interval.
  MachineResult[bool](status: MachineError.None, completed: true)

proc readableRange*(memory: Memory, address: MemoryAddress, length: MemoryLength): MachineResult[bool] =
  ## Inspect a complete natural readable interval without allocating payload bytes or applying a caller copy budget.
  ## The physical 4-GiB domain bounds scanning; empty intervals ignore the pointer but still validate the owner.
  inspectRange(memory, address, length, MemoryByteLimit(0x100000000'u64), false)

proc writableRange*(memory: Memory, address: MemoryAddress, length: MemoryLength): MachineResult[bool] =
  ## Inspect a complete natural writable interval without mutation, preserving the first physical fault reason.
  ## Host dispatchers can establish permission precedence before ID lookup and independent local copying policy.
  inspectRange(memory, address, length, MemoryByteLimit(0x100000000'u64), true)

proc copyPageOut(page: PageData, offset: int, output: var seq[byte], first, count: int)
    {.requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 4096-offset and
      first >= 0 and first < output.len and count <= output.len-first.} =
  ## Copy immutable owned chunks into a fresh independent result; no source byte pointer escapes.
  var copied = 0
  while copied < count:
    # Each batch stays inside one512-byte source allocation and the already-sized destination.
    let position = offset+copied
    let within = position mod 512
    let batch = min(count-copied, 512-within)
    copyMem(addr output[first+copied], unsafeAddr page.chunks[position div 512].bytes[within], batch)
    copied += batch

proc copyPageIn(page: PageData, offset: int, input: openArray[byte], first, count: int)
    {.requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 4096-offset and
      first >= 0 and first < input.len and count <= input.len-first.} =
  ## The caller cloned every touched chunk; borrowed public input cannot alias private snapshot storage.
  var copied = 0
  while copied < count:
    # Disjoint raw byte copies have no endian conversion and never cross an allocation boundary.
    let position = offset+copied
    let within = position mod 512
    let batch = min(count-copied, 512-within)
    copyMem(addr page.chunks[position div 512].bytes[within], unsafeAddr input[first+copied], batch)
    copied += batch

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
  var at = 0
  if size > 0:
    at = lowerBound(data, uint32(uint64(address) div 4096)) # Empty intervals never inspect or narrow their ignored pointer.
  while copied < size:
    # The preflight proved all addresses and native index conversions before allocation.
    let physical = uint64(address) + uint64(copied)
    let offset = int(physical mod 4096)
    let count = min(size - copied, 4096 - offset)
    copyPageOut(data.pages[at], offset, bytes, copied, count)
    copied += count
    inc at # Complete preflight proved each consecutive physical page occupies the next sorted slot.
  MachineResult[seq[byte]](status: MachineError.None, completed: bytes)

proc writeBytes*(memory: Memory, address: MemoryAddress, input: openArray[byte],
    limit: MemoryByteLimit): MachineResult[Memory] =
  ## Validate the complete host span before cloning only its touched page-reference blocks and chunks.
  let checked = inspectRange(memory, address, MemoryLength(uint64(input.len)), limit, true)
  if checked.error != MachineError.None: return failure[Memory, bool](checked)
  if input.len == 0:
    # A zero-length write preserves the original immutable owner and policy.
    return MachineResult[Memory](status: MachineError.None, completed: memory)
  if memory.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  let data = memory.data
  var slots = newSeqOfCap[int](input.len div 4096+2)
  var changed = newSeqOfCap[PageData](input.len div 4096+2)
  var copied = 0
  var at = lowerBound(data, uint32(uint64(address) div 4096))
  while copied < input.len:
    # Preflight proved a nonwrapping readable/writable sequence; each page gets one private header.
    let physical = uint64(address)+uint64(copied)
    let offset = int(physical mod 4096)
    let count = min(input.len-copied, 4096-offset)
    var page = writablePageClone(data.pages[at], offset, count)
    copyPageIn(page, offset, input, copied, count)
    slots.add(at)
    changed.add(move(page))
    copied += count
    inc at
  var directory = replacedDirectory(data.pages, slots, changed)
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: move(directory), limit: data.limit)))

proc newScalarMemoryWriter*(memory: Memory): MachineResult[ScalarMemoryWriter] =
  ## Retain a genuine immutable base; working vectors/chunks allocate only after a complete successful scalar preflight.
  if memory.data == nil: return MachineResult[ScalarMemoryWriter](status: MachineError.InvalidOwner)
  MachineResult[ScalarMemoryWriter](status: MachineError.None, completed:
    ScalarMemoryWriter(base: memory, pages: @[], dirty: @[], active: false, recent: [-1, -1],
        pageSlots: default(array[64, uint32]), writePrivate: 0, spareWritePrivate: 0))

proc cloneWriterChunk(writer: ScalarMemoryWriter, slot, chunk: int, mask: byte) {.noinline.} =
  ## Keep allocator/TLS work on the first-write path; callers prove this chunk is not yet private.
  writer.readPage = nil # A prior readable header may be the immutable page being replaced.
  if writer.dirty[slot] == 0:
    writer.pages[slot] = pageWithAccess(writer.pages[slot], writer.pages[slot].access)
  writer.pages[slot].chunks[chunk] = PageChunk(bytes: writer.pages[slot].chunks[chunk].bytes)
  writer.dirty[slot] = writer.dirty[slot] or mask

proc prepareWriterSpan(writer: ScalarMemoryWriter, slot, offset, count: int) =
  ## Already-private chunks need only a bounded dirty-bit check; clone before the first byte mutation.
  let first = offset div 512
  let last = (offset+count-1) div 512
  for chunk in first..last:
    let mask = 1'u8 shl chunk
    if (writer.dirty[slot] and mask) == 0:
      cloneWriterChunk(writer, slot, chunk, mask) # No immutable header/chunk is ever changed in place.

func writerScalar(writer: ScalarMemoryWriter, source: MemoryData, slot, offset,
    count: int): uint64 {.inline.} =
  ## Read the latest epoch's selected page, or the unchanged immutable base before activation.
  if writer.active: pageScalar(writer.pages[slot], offset, count)
  else: pageScalar(source.pages[slot], offset, count)

proc rememberScalarSpan(writer: ScalarMemoryWriter, span: ScalarSpan) =
  ## Only complete successful preflight supplies slots; epoch sealing retains their exact sorted page positions.
  if span.first != span.last:
    writer.recent = [span.first, span.last]
  elif writer.recent[0] != span.first:
    writer.recent[1] = writer.recent[0]
    writer.recent[0] = span.first

proc loadWriterMiss(writer: ScalarMemoryWriter, source: MemoryData, address: MemoryAddress,
    width: AccessWidth): MachineResult[RegisterValue] {.noinline.} =
  ## Keep full span resolution and readable-window admission on a separate checked miss path; the caller retains this genuine base.
  let start = uint64(address) and 0xffffffff'u64
  let checked = scalarSpan[true, false](writer.base, address, width, writer.recent,
      addr writer.pageSlots)
  if checked.error != MachineError.None: return failure[RegisterValue, ScalarSpan](checked)
  let span = checked.value
  rememberScalarSpan(writer, span)
  if span.first == span.last:
    # Only complete preflight can admit a new readable owner; permission changes require a new writer.
    writer.readTag = start shr 12
    if writer.active: writer.readPage = writer.pages[span.first]
    else: writer.readPage = source.pages[span.first]
  var value = writerScalar(writer, source, span.first, span.offset, span.firstCount)
  if span.firstCount < span.count:
    # Full preflight precedes both reads; the remaining suffix proves a bounded sub-word shift.
    value = value or (writerScalar(writer, source, span.last, 0, span.count-span.firstCount) shl (
        8*span.firstCount))
  MachineResult[RegisterValue](status: MachineError.None, completed: RegisterValue(value))

proc loadScalar[selectedWidth: static[int]](writer: nil ScalarMemoryWriter, address: MemoryAddress,
    width: AccessWidth): MachineResult[RegisterValue] {.inline.} =
  ## Read the writer's latest scalar state; nil/default-invalid builders never imply a zero-filled address space.
  if writer == nil: return MachineResult[RegisterValue](status: MachineError.InvalidOwner)
  let source {.cursor.} = writer.base.data # The retained writer fixes this immutable base throughout the callback-free operation.
  if source == nil: return MachineResult[RegisterValue](status: MachineError.InvalidOwner)
  let start = uint64(address) and 0xffffffff'u64
  let count = when selectedWidth > 0: selectedWidth else: int(byte(width))
  let within = int(start and 4095'u64)
  if (count == 1 or count == 2 or count == 4 or count == 8) and start >= 0x10000'u64 and
      start <= uint64(high(uint32))-uint64(count) and within <= 4096-count:
    # Exact page identity retains a complete readable extent; page/chunk byte helpers stay checked.
    let tag = start shr 12
    let writable {.cursor.} = writer.writePage
    if writable != nil and writer.writeTag == tag:
      return MachineResult[RegisterValue](status: MachineError.None,
        completed: RegisterValue(pageScalar(writable, within, count)))
    let spare {.cursor.} = writer.spareWritePage
    if spare != nil and writer.spareWriteTag == tag:
      return MachineResult[RegisterValue](status: MachineError.None,
        completed: RegisterValue(pageScalar(spare, within, count)))
    let readable {.cursor.} = writer.readPage
    if readable != nil and writer.readTag == tag:
      return MachineResult[RegisterValue](status: MachineError.None,
        completed: RegisterValue(pageScalar(readable, within, count)))
  loadWriterMiss(writer, source, address, width)

proc load*(writer: nil ScalarMemoryWriter, address: MemoryAddress,
    width: AccessWidth): MachineResult[RegisterValue] {.inline.} =
  ## Runtime widths retain the original complete checked scalar path.
  loadScalar[0](writer, address, width)

proc load*[Width: static[int]](writer: nil ScalarMemoryWriter,
    address: MemoryAddress): MachineResult[RegisterValue] {.inline, requires: Width == 1 or Width ==
        2 or Width == 4 or Width == 8.} =
  ## A constant supported width specializes byte access while retaining owner, extent, permission and epoch checks.
  loadScalar[Width](writer, address, AccessWidth(byte(Width)))

proc storeWriterMiss(writer: ScalarMemoryWriter, source: MemoryData, address: MemoryAddress,
    width: AccessWidth, value: RegisterValue): MachineResult[bool] {.noinline.} =
  ## Complete original preflight and COW preparation precede every miss mutation; cached single-page hits remain in the small caller.
  let start = uint64(address) and 0xffffffff'u64
  let checked = scalarSpan[true, true](writer.base, address, width, writer.recent,
      addr writer.pageSlots)
  if checked.error != MachineError.None: return failure[bool, ScalarSpan](checked)
  if not writer.active:
    # Page count and vector extent already belong to the admitted base; no write can insert pages or change permissions.
    writer.pages = newSeqOfCap[PageData](source.pages.len)
    writer.dirty = newSeq[byte](source.pages.len)
    for index in 0..<source.pages.len: writer.pages.add(source.pages[
        index]) # Retain immutable source pages through checked indexed reads.
    writer.active = true
  let span = checked.value
  rememberScalarSpan(writer, span)
  prepareWriterSpan(writer, span.first, span.offset, span.firstCount)
  if span.firstCount < span.count:
    prepareWriterSpan(writer, span.last, 0, span.count-span.firstCount)
  if span.first == span.last:
    # First-write preparation established the private header before retaining it for later accesses.
    writer.spareWritePrivate = writer.writePrivate
    writer.spareWritePage = writer.writePage # Only a genuine miss rotates the bounded retained owners.
    writer.spareWriteTag = writer.writeTag
    writer.spareWriteSlot = writer.writeSlot
    writer.writeTag = start shr 12
    writer.writeSlot = span.first
    writer.writePage = writer.pages[span.first]
    writer.writePrivate = writer.dirty[span.first]
  setPageScalar(writer.pages[span.first], span.offset, span.firstCount, uint64(value))
  if span.firstCount < span.count:
    # Both private page spans were prepared before mutation; source/snapshot aliases remain immutable.
    setPageScalar(writer.pages[span.last], 0, span.count-span.firstCount, uint64(value) shr (
        8*span.firstCount))
  MachineResult[bool](status: MachineError.None, completed: true)

func privateMaskCovers(mask: byte, offset, count: int): bool {.inline,
    requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 8 and count <=
        4096-offset.} =
  ## A private epoch mask may only suppress checks for chunks already proved exclusive by the original COW path.
  if offset mod 512 > 512-count: return false
  let wanted = 1'u8 shl (offset div 512)
  (mask and wanted) == wanted

proc storeScalar[selectedWidth: static[int]](writer: nil ScalarMemoryWriter, address: MemoryAddress,
    width: AccessWidth, value: RegisterValue): MachineResult[bool] {.inline.} =
  ## Commit one atomic private scalar write; failures preserve all previous successful writes and expose only their reason.
  if writer == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  let source {.cursor.} = writer.base.data # The retained writer fixes this immutable base throughout the callback-free operation.
  if source == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  let start = uint64(address) and 0xffffffff'u64
  let count = when selectedWidth > 0: selectedWidth else: int(byte(width))
  let within = int(start and 4095'u64)
  let writable {.cursor.} = writer.writePage
  if writable != nil and (count == 1 or count == 2 or count == 4 or count == 8) and
      start >= 0x10000'u64 and start <= uint64(high(uint32))-uint64(count) and
      within <= 4096-count and writer.writeTag == start shr 12:
    # Only a mask bound to this exact retained header/epoch can prove every touched chunk already private.
    if count == 1:
      # Byte stores retain their cheaper original dirty-vector check; any newly private bits remain safe underclaims here.
      prepareWriterSpan(writer, writer.writeSlot, within, count)
    elif not privateMaskCovers(writer.writePrivate, within, count):
      prepareWriterSpan(writer, writer.writeSlot, within, count)
      writer.writePrivate = writer.dirty[writer.writeSlot]
    setPageScalar(writable, within, count, uint64(value))
    return MachineResult[bool](status: MachineError.None, completed: true)
  let spare {.cursor.} = writer.spareWritePage
  if spare != nil and (count == 1 or count == 2 or count == 4 or count == 8) and
      start >= 0x10000'u64 and start <= uint64(high(uint32))-uint64(count) and
      within <= 4096-count and writer.spareWriteTag == start shr 12:
    # Spare facts travel with the same private header; unknown bits still take the original complete-span COW path.
    if count == 1:
      # Byte stores retain their cheaper original dirty-vector check; any newly private bits remain safe underclaims here.
      prepareWriterSpan(writer, writer.spareWriteSlot, within, count)
    elif not privateMaskCovers(writer.spareWritePrivate, within, count):
      prepareWriterSpan(writer, writer.spareWriteSlot, within, count)
      writer.spareWritePrivate = writer.dirty[writer.spareWriteSlot]
    setPageScalar(spare, within, count, uint64(value))
    return MachineResult[bool](status: MachineError.None, completed: true)
  storeWriterMiss(writer, source, address, width, value)

proc store*(writer: nil ScalarMemoryWriter, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue): MachineResult[bool] {.inline.} =
  ## Runtime widths retain the original atomic private writer path.
  storeScalar[0](writer, address, width, value)

proc store*[Width: static[int]](writer: nil ScalarMemoryWriter, address: MemoryAddress,
    value: RegisterValue): MachineResult[bool] {.inline, requires: Width == 1 or Width == 2 or
        Width == 4 or Width == 8.} =
  ## A constant width specializes the same COW-preflight and atomic write; snapshots still retire every window.
  storeScalar[Width](writer, address, AccessWidth(byte(Width)), value)

proc snapshotMemory*(writer: nil ScalarMemoryWriter): MachineResult[Memory] =
  ## Seal the current epoch by transferring its private vector; all writer aliases resume from this immutable owner on later writes.
  if writer == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  let source = writer.base.data
  if source == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  writer.readPage = nil # All cached aliases retire before an immutable snapshot becomes observable.
  writer.writePage = nil
  writer.spareWritePage = nil # No cached private capability survives sealing through any alias.
  writer.writePrivate = 0
  writer.spareWritePrivate = 0
  if not writer.active:
    return MachineResult[Memory](status: MachineError.None,
        completed: writer.base) # No new write means no new snapshot allocation.
  let frozen = Memory(data: MemoryData(pages: pageDirectory(move(writer.pages)),
      limit: source.limit))
  writer.base = frozen
  writer.dirty = @[]
  writer.active = false # No mutable chunk/vector alias survives the transfer; future stores clone a new epoch.
  MachineResult[Memory](status: MachineError.None, completed: frozen)

proc captureMachine*(program: Program, memory: Memory, info: MachineInfo): MachineResult[Machine] =
  ## Capture a validated entry location and copied CPU values; this is not standard JAM initialization.
  # Empty/default memory must be distinguished from a valid all-inaccessible memory snapshot.
  if memory.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  if uint64(info.gasDeficit) != 0:
    # Negative balances are terminal state and cannot be captured as executable guest input.
    return MachineResult[Machine](status: MachineError.InvalidGasState)
  # Validate owner, address and opcode marker without reconstructing unused operands.
  if instructionOpcode(program, info.pc).error != ProgramError.None:
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
  if uint64(info.gasDeficit) != 0:
    # The current paper has one unsigned balance; legacy nonzero deficit input is invalid.
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
