# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable PVM CPU and sparse memory snapshots.
##
## Machines copy register, PC and gas metadata and retain their exact immutable program
## and memory. Environment capture accepts an executable PC. Terminal capture can keep
## the trap PC beyond code because the outcome, not a resumable instruction, owns it.
##
## The two-level page directory shares unchanged reference blocks of up to 64 entries.
## A page retains permissions and eight logical 512-byte spans. A span can use a
## shared backing range or an explicit chunk owner. Absent slots are inaccessible,
## while a retained inaccessible page can keep bytes for remapping. Writers copy
## the affected spans and directory paths only after complete preflight.
##
## Scalar access uses the scoped PolkaVM overflow and presence precedence recorded
## in spec/pvm-machine.md. Host range inspection has its own typed bounds and errors.

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
  InitializationSource* {.pure.} = enum ## Select one of the two borrowed inputs for a mapped prefix.
    First, Second
  InitializationRegion* = object ## A mapped page interval with a copied prefix from an explicit input.
    first*, past*: PageIndex
    access*: PageAccess
    source*: InitializationSource
    offset*, length*: int
  MemoryPageSlot* = distinct uint32 ## Position within the supplied immutable owner's sorted mapping, separate from a physical page ordinal.
  PageDescription* = object ## Copied mapping metadata grants no mutable page storage or guest access permission.
    index*: PageIndex
    access*: PageAccess
  MachineError* {.pure.} = enum ## Local API failures are distinct from guest panic/fault, with retained historical error identifiers.
    Uninitialized, None, InvalidOwner, InvalidPage, UnsortedPages, LimitExceeded,
    InvalidWidth, InvalidRegister, InvalidProgram, Panic, Fault, AmbiguousAccessOrder, InvalidRange,
      InvalidGasState,
    AllocationRefused
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
  # Full input pages share seven immutable spans through one owner; the eighth stays an ordinary chunk.
  PageBacking = ref object
    bytes: array[3584, byte]
  # Each effective chunk is an override or a span in backing; index7 always has an ordinary owner.
  PageData = ref object
    index: PageIndex
    access: PageAccess
    zeroChunks: uint8 # Set bits prove complete zero chunks; clear bits mean unknown.
    backing: nil PageBacking
    chunks: array[8, nil PageChunk]
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
  ResidentReplacementBatch* = object ## Internal frame publication owns completed replacements only.
    source: Memory
    status: MachineError
    lastSlot: int
    slots: seq[int]
    changed: seq[PageData]
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

func `==`*(left, right: PageIndex): bool {.inline.} =
  ## Compare page ordinals within their nominal domain; other memory indices stay distinct.
  uint32(left) == uint32(right)

func `==`*(left, right: MemoryPageSlot): bool {.inline.} =
  ## Compare sorted mapping positions without accepting physical page ordinals.
  uint32(left) == uint32(right)

func `==`*(left, right: PageAddress): bool {.inline.} =
  ## Compare aligned fault addresses without treating them as page ordinals.
  uint32(left) == uint32(right)

func `==`*(left, right: PageCount): bool {.inline.} =
  ## Compare materialized-page counts without accepting page indices or allocation policies.
  uint32(left) == uint32(right)

func `==`*(left, right: RegisterValue): bool {.inline.} =
  ## Compare register words without admitting addresses, gas balances or other nominal domains.
  uint64(left) == uint64(right)

func `==`*(left, right: MachineGas): bool {.inline.} =
  ## Compare complete gas balances within their unsigned nominal domain.
  uint64(left) == uint64(right)

func `==`*(left, right: GasDeficit): bool {.inline.} =
  ## Compare terminal deficit magnitudes without mixing them with spendable gas balances.
  uint64(left) == uint64(right)

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
  # Quotient and remainder count the last partial block without adding to the admitted page count.
  let blockCount = owned.len div 64 + int(owned.len mod 64 != 0)
  result = PageDirectory(len: owned.len, blocks: newSeqOfCap[PageBlock](blockCount))
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
    replacements: openArray[PageData], directory: var PageDirectory): MachineError =
  ## All callers preflight before construction; copy the root and clone each affected block exactly once.
  if slots.len != replacements.len: return MachineError.InvalidRange
  var built = PageDirectory(len: pages.len, blocks: newSeqOfCap[PageBlock](pages.blocks.len))
  if pages.blocks.len > 0 and built.blocks.rawData == nil: return MachineError.LimitExceeded
  for index in 0..<pages.blocks.len:
    # Unchanged immutable blocks retain their shared children rather than retaining every page anew.
    built.blocks.add(pages.blocks[index])
  var previous = -1
  var previousGroup = -1
  for index in 0..<slots.len:
    # Strict ascending slots make repeated changes within a block share one fresh private copy.
    let slot = slots[index]
    if slot < 0 or slot >= pages.len or slot <= previous: return MachineError.InvalidRange
    let group = slot div 64
    if group != previousGroup:
      # The old block remains immutable through its retained source root.
      var entries = newSeqOfCap[PageData](pages.blocks[group].entries.len)
      if entries.rawData == nil: return MachineError.LimitExceeded
      for offset in 0..<pages.blocks[group].entries.len:
        # Copy only this block's initialized references; no mutable sequence is shared.
        entries.add(pages.blocks[group].entries[offset])
      let copied: nil PageBlock = PageBlock()
      if copied == nil: return MachineError.LimitExceeded
      copied.entries = move(entries)
      built.blocks[group] = copied
      previousGroup = group
    built.blocks[group].entries[slot and 63] = replacements[index]
    previous = slot
  directory = move(built)
  MachineError.None

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

func borrowPageChunk(page: PageData, slot: int, within = 0): ptr byte
    {.inline, requires: slot >= 0 and slot < 8 and within >= 0 and within < 512.} =
  ## Private read-only borrow: retain the unchanged page through the immediate byte read or copy.
  ## The offset names one initialized byte; a copying caller also proves count <= 512-within.
  ## This pointer owns nothing and is never stored or exported.
  let owned {.cursor.} = page.chunks[slot]
  if owned != nil:
    return unsafeAddr owned.bytes[within]
  let backing {.cursor.} = page.backing
  assert backing != nil and slot < 7
  # The checked slot/within prove this real-array index is at most3583 before taking its address.
  unsafeAddr backing.bytes[slot*512+within]

proc copiedChunk(input: openArray[byte], first: int): PageChunk {.requires:
    first >= 0 and first <= input.len and 512 <= input.len-first.} =
  ## Capture one complete borrowed span; no caller pointer survives the initialized owner.
  result = PageChunk(bytes: default(array[512, byte]))
  copyMem(addr result.bytes[0], unsafeAddr input[first], 512)

proc fullPage(index: PageIndex, access: PageAccess, input: openArray[byte]): PageData
    {.requires: input.len == 4096.} =
  ## Copy a complete unknown page into a seven-span backing and a final chunk.
  ## Optional overrides keep later writes at 512-byte copy granularity. A backing
  ## remains alive until every covered span has its own complete override.
  let backing = PageBacking(bytes: default(array[3584, byte]))
  copyMem(addr backing.bytes[0], unsafeAddr input[0], 3584)
  let tail = copiedChunk(input, 3584)
  PageData(index: index, zeroChunks: 0, access: access, backing: backing,
    chunks: [nil, nil, nil, nil, nil, nil, nil, tail])

proc pageFromImage(image: PageImage): PageData =
  ## Caller-owned full images remain unknown even if all their copied bytes happen to be zero.
  fullPage(image.index, image.access, image.bytes)

proc copiedPageChunk(page: PageData, slot: int): PageChunk {.requires:
    slot >= 0 and slot < 8.} =
  ## Allocate before borrowing, then copy exactly one effective span; never return an owning array temporary.
  result = PageChunk(bytes: default(array[512, byte]))
  copyMem(addr result.bytes[0], borrowPageChunk(page, slot), 512)

proc dropCoveredBacking(page: PageData) =
  ## Only complete override coverage releases the base; nullable owners never certify writer privacy.
  if page.backing == nil: return
  for slot in 0..<7:
    # A missing override still needs its corresponding immutable base span.
    if page.chunks[slot] == nil: return
  page.backing = nil

proc pageFromReplacement(previous: PageData, image: PageImage): PageData =
  ## Preserve a fresh page identity and unknown provenance, sharing every unchanged effective span.
  var chunks = default(array[8, nil PageChunk])
  for slot in 0..<8:
    # The retained previous page owns this immediate borrow; allocation follows comparison.
    if cmpMem(borrowPageChunk(previous, slot), unsafeAddr image.bytes[slot*512], 512) != 0:
      chunks[slot] = copiedChunk(image.bytes, slot*512)
    else:
      # Retain unchanged overrides only; nil continues to select the same immutable backing.
      chunks[slot] = previous.chunks[slot]
  result = PageData(index: image.index, zeroChunks: 0, access: image.access,
    backing: previous.backing, chunks: move(chunks))
  dropCoveredBacking(result)

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
  PageData(index: index, zeroChunks: 255, access: access, backing: nil,
    chunks: [chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk])

proc initializationPage(index: PageIndex, access: PageAccess, input: openArray[byte],
    offset, count: int, zero: var nil PageChunk): nil PageData =
  ## The admitted source span fits in one page. Publish it only after every payload owner exists.
  let page: nil PageData = PageData(index: index, access: access)
  if page == nil: return nil
  if count == 4096:
    let backing: nil PageBacking = PageBacking()
    if backing == nil: return nil
    let tail: nil PageChunk = PageChunk()
    if tail == nil: return nil
    copyMem(addr backing.bytes[0], unsafeAddr input[offset], 3584)
    copyMem(addr tail.bytes[0], unsafeAddr input[offset+3584], 512)
    page.backing = backing
    page.chunks[7] = tail
  else:
    for slot in 0..<8:
      let start = slot*512
      if start >= count:
        if zero == nil: zero = PageChunk()
        if zero == nil: return nil
        page.zeroChunks = page.zeroChunks or (1'u8 shl slot)
        page.chunks[slot] = zero
      else:
        let chunk: nil PageChunk = PageChunk()
        if chunk == nil: return nil
        copyMem(addr chunk.bytes[0], unsafeAddr input[offset+start], min(512, count-start))
        page.chunks[slot] = chunk
  page

proc appendInitializationRegion(directory: var PageDirectory, total: int,
    region: InitializationRegion, input: openArray[byte], zero: var nil PageChunk): bool =
  ## The capture owns the entire partial directory until all regions have succeeded.
  var offset = region.offset
  var remaining = region.length
  for ordinal in uint32(region.first)..<uint32(region.past):
    if directory.len mod 64 == 0:
      var entries = newSeqOfCap[PageData](min(64, total-directory.len))
      if entries.rawData == nil: return false
      let blockOwner: nil PageBlock = PageBlock()
      if blockOwner == nil: return false
      blockOwner.entries = move(entries)
      directory.blocks.add(blockOwner)
    let count = min(remaining, 4096)
    let page = initializationPage(PageIndex(ordinal), region.access, input, offset, count, zero)
    if page == nil: return false
    directory.blocks[directory.len div 64].entries.add(page)
    inc directory.len
    offset += count
    remaining -= count
  true

proc captureInitializationMemory*(regions: openArray[InitializationRegion],
    first, second: openArray[byte], limit: PageLimit): MachineResult[Memory] =
  ## Capture sorted mapped prefixes from two explicit inputs, zero-filling every absent suffix.
  ## All descriptors and source extents are checked before allocation. No borrowed bytes escape.
  ## If a page or directory allocation fails, release the private partial directory
  ## and return `MachineError.LimitExceeded`.
  var total = 0'u64
  var previousPast = 0'u32
  for index in 0..<regions.len:
    let region = regions[index]
    let firstPage = uint32(region.first)
    let pastPage = uint32(region.past)
    if firstPage > pastPage or pastPage > 0x100000'u32:
      return MachineResult[Memory](status: MachineError.InvalidRange) # Exclusive endpoint may equal 2^20.
    let count = uint64(pastPage-firstPage)
    let sourceLen = if region.source == InitializationSource.First: first.len else: second.len
    if region.offset < 0 or region.offset > sourceLen or region.length < 0 or
        region.length > sourceLen-region.offset or uint64(region.length) > count*4096:
      return MachineResult[Memory](status: MachineError.InvalidRange) # Empty mappings require an empty prefix.
    if firstPage != pastPage:
      if firstPage < previousPast:
        return MachineResult[Memory](status: MachineError.UnsortedPages) # Reject overlap with any earlier mapping.
      previousPast = pastPage
      # Sorted disjoint intervals lie in the fixed physical domain, so their sum is at most 2^20.
      total += count
  if total > uint64(uint32(limit)) or total > uint64(high(int) div sizeof(PageData)):
    return MachineResult[Memory](status: MachineError.LimitExceeded) # Count all mapped pages, including padding.
  let blockCount = int(total) div 64 + int(total mod 64 != 0)
  var directory = PageDirectory(blocks: newSeqOfCap[PageBlock](blockCount))
  if blockCount > 0 and directory.blocks.rawData == nil:
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  var zero: nil PageChunk = nil
  for region in regions:
    let captured = case region.source
      of InitializationSource.First: appendInitializationRegion(directory, int(total), region,
          first, zero)
      of InitializationSource.Second: appendInitializationRegion(directory, int(total), region,
          second, zero)
    if not captured: return MachineResult[Memory](status: MachineError.LimitExceeded)
  let owner: nil MemoryData = MemoryData(limit: limit)
  if owner == nil: return MachineResult[Memory](status: MachineError.LimitExceeded)
  owner.pages = move(directory)
  MachineResult[Memory](status: MachineError.None, completed: Memory(data: owner))

proc appendedDirectory(pages: PageDirectory, first, past: PageIndex, access: PageAccess,
    total: int): PageDirectory =
  ## An admitted append shares complete immutable blocks and privately fills only the old partial tail.
  assert uint32(first) < uint32(past) and uint32(past) <= 0x100000'u32
  assert total >= pages.len and total <= 0x100000
  assert uint32(total-pages.len) == uint32(past)-uint32(first)
  let complete = pages.len div 64
  let remainder = pages.len mod 64
  let blockCount = total div 64 + int(total mod 64 != 0)
  result = PageDirectory(len: total, blocks: newSeqOfCap[PageBlock](blockCount))
  for group in 0..<complete:
    # Sharing a block retains one owner without retaining its sixty-four page children again.
    result.blocks.add(pages.blocks[group])
  var entries = newSeqOfCap[PageData](min(64, total-complete*64))
  for offset in 0..<remainder:
    # Only initialized final-block references enter the private replacement tail.
    entries.add(pages.blocks[complete].entries[offset])
  var zero: nil PageChunk = nil
  var ordinal = uint32(first)
  while ordinal < uint32(past):
    # The caller proves every new ordinal follows all old pages; existing chunks stay immutable.
    entries.add(zeroPage(PageIndex(ordinal), access, zero))
    inc ordinal
    if entries.len == 64:
      # Publish a complete private block once; an exact fill must not allocate an empty final block.
      result.blocks.add(PageBlock(entries: move(entries)))
      if ordinal < uint32(past):
        # The validated remaining ordinal count bounds this final capacity and its native conversion.
        entries = newSeqOfCap[PageData](min(64, int(uint32(past)-ordinal)))
  if entries.len != 0:
    # A partial final block exposes exactly its initialized entries, never spare capacity.
    result.blocks.add(PageBlock(entries: move(entries)))
  assert result.blocks.len == blockCount

func pageByte(page: PageData, offset: int): byte {.inline.} =
  ## Read one proven effective span without retaining a transient reference or exposing its borrow.
  borrowPageChunk(page, offset div 512, offset mod 512)[]

func pageScalar(page: PageData, offset, count: int): uint64 {.inline,
    requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 8 and count <=
        4096-offset.} =
  ## Resolve one immutable span into a private initialized word; no borrowed address escapes.
  result = 0
  if count == 1: return uint64(pageByte(page, offset))
  let chunk = offset div 512
  let within = offset mod 512
  if within <= 512-count:
    let source = borrowPageChunk(page, chunk, within)
    # Disjoint stack and immutable heap storage permit an unaligned-safe copy only after proving the entire source extent.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      case count
      of 2:
        # Fixed admitted widths lower to unaligned-safe native loads without a variable copy call.
        copyMem(addr result, source, 2)
      of 4:
        # Copy the complete half-register span after the same permission and chunk preflight.
        copyMem(addr result, source, 4)
      of 8:
        # A full register still reads exactly eight bytes, including unaligned offsets.
        copyMem(addr result, source, 8)
      else:
        # Page-fragment widths retain the original bounded byte-count copy.
        copyMem(addr result, source, count)
      return # Little-endian hosts now hold the exact zero-extended guest word.
  for index in 0..<count:
    # Big-endian hosts and chunk-crossing spans retain the portable byte-wise equation.
    result = result or (uint64(pageByte(page, offset+index)) shl (8*index))

proc imageFromPage(page: PageData): PageImage =
  ## Materialize the public copied image; chunk sharing never escapes through observation.
  result = PageImage(index: page.index, access: page.access, bytes: default(array[4096, byte]))
  for slot in 0..<8:
    # Resolve each effective span once and copy512 bytes into the fresh independent image.
    copyMem(addr result.bytes[slot*512], borrowPageChunk(page, slot), 512)

proc pageWithAccess(page: PageData, access: PageAccess): PageData =
  ## Permission-only successors share base/override owners without changing predecessor access or bytes.
  PageData(index: page.index, zeroChunks: page.zeroChunks, access: access,
    backing: page.backing, chunks: page.chunks)

proc writablePageClone(page: PageData, offset, count: int): PageData =
  ## Callers preflight a nonempty interval within this page; clone its header and only touched chunks before mutation.
  result = pageWithAccess(page, page.access)
  result.zeroChunks = 0 # Private mutation clears all inherited zero claims before the first byte store.
  let first = offset div 512
  let last = (offset+count-1) div 512
  for slot in first..last:
    result.chunks[slot] = copiedPageChunk(page, slot) # Untouched effective spans remain shared.
  dropCoveredBacking(result)

proc setPageByte(page: PageData, offset: int, value: byte) {.inline.} =
  ## Only private writable clones reach this helper, and their touched chunk was copied before the first write.
  let target {.cursor.} = page.chunks[offset div 512]
  assert target != nil # Complete clone/epoch preflight, not this owner test, grants write authority.
  target.bytes[offset mod 512] = value

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
    let target {.cursor.} = page.chunks[chunk]
    assert target != nil # The caller proved exclusive ownership before entering this helper.
    # Copy only a complete admitted span from a disjoint initialized stack word into the private chunk.
    var endian = 1'u16
    var tag = default(array[2, byte])
    copyMem(addr tag[0], addr endian, 2)
    if tag[0] == 1:
      var word = value
      case count
      of 2:
        # Fixed admitted widths permit native unaligned-safe stores after private-chunk preparation.
        copyMem(addr target.bytes[within], addr word, 2)
      of 4:
        # Only the low four little-endian bytes replace this proven private extent.
        copyMem(addr target.bytes[within], addr word, 4)
      of 8:
        # The full register replaces exactly the admitted eight-byte span.
        copyMem(addr target.bytes[within], addr word, 8)
      else:
        # Cross-page fragments retain their original exact-width copy.
        copyMem(addr target.bytes[within], addr word, count)
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
  # Final private backing/tail owners copy every byte; no caller-owned pointer survives this call.
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
  ## A refused allocation returns no positions. A truncated delta would leave stale private bytes.
  let left = before.data
  let right = after.data
  if left == nil or right == nil: return MachineResult[seq[MemoryPageSlot]](
      status: MachineError.InvalidOwner)
  if left == right: return MachineResult[seq[MemoryPageSlot]](
      status: MachineError.None, completed: @[])
  if left.pages.len != right.pages.len:
    return MachineResult[seq[MemoryPageSlot]](status: MachineError.InvalidRange)
  var count = 0
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
      inc count
  var changed = newSeqUninit[MemoryPageSlot](count)
  if changed.len != count:
    return MachineResult[seq[MemoryPageSlot]](status: MachineError.AllocationRefused)
  var index = 0
  for group in 0..<left.pages.blocks.len:
    # Ascending groups and positions produce sorted slots without sorting or copying page payloads.
    if left.pages.blocks[group] == right.pages.blocks[group]: continue
    let first = group*64
    let past = min(first+64, left.pages.len)
    for slot in first..<past:
      if left.pages[slot] != right.pages[slot]:
        changed[index] = MemoryPageSlot(uint32(slot))
        inc index
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
  ## Copy the complete sorted layout. A default owner or a refused allocation
  ## produces only a local error.
  let data = memory.data
  if data == nil:
    return MachineResult[seq[PageDescription]](status: MachineError.InvalidOwner)
  var pages = newSeq[PageDescription](data.pages.len)
  if pages.len != data.pages.len:
    return MachineResult[seq[PageDescription]](status: MachineError.AllocationRefused)
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
    # Each effective512-byte span copies completely into its disjoint portion of the output page.
    copyMem(addr output[chunk*512], borrowPageChunk(page, chunk), 512)
  MachineResult[PageDescription](status: MachineError.None,
    completed: PageDescription(index: page.index, access: page.access))

func memoryPageIsKnownZero*(memory: Memory, slot: MemoryPageSlot,
    expected: PageDescription): MachineResult[bool] =
  ## True proves all bytes zero in this exact immutable source page; false means unknown, never nonzero.
  let data = memory.data
  if data == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  if uint64(slot) >= uint64(data.pages.len):
    # The complete sorted-slot check precedes narrowing or any directory access.
    return MachineResult[bool](status: MachineError.InvalidRange)
  let page {.cursor.} = data.pages[int(uint32(slot))]
  if page.index != expected.index or page.access != expected.access:
    # Match coordinates/access, then read the zero fact only from this supplied immutable owner.
    return MachineResult[bool](status: MachineError.InvalidRange)
  MachineResult[bool](status: MachineError.None, completed: page.zeroChunks == 255)

proc matchesMemoryPageBytes*(memory: Memory, slot: MemoryPageSlot,
    expected: PageDescription, bytes: openArray[byte]): MachineResult[bool] =
  ## Compare a borrowed private page with an immutable captured page; no source bytes or alias escape.
  let data = memory.data
  if data == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  if uint64(slot) >= uint64(data.pages.len) or bytes.len != 4096:
    return MachineResult[bool](status: MachineError.InvalidRange)
  let page {.cursor.} = data.pages[int(uint32(slot))]
  if page.index != expected.index or page.access != expected.access:
    return MachineResult[bool](status: MachineError.InvalidRange)
  for chunk in 0..<8:
    if cmpMem(borrowPageChunk(page, chunk), unsafeAddr bytes[chunk*512], 512) != 0:
      return MachineResult[bool](status: MachineError.None, completed: false)
  MachineResult[bool](status: MachineError.None, completed: true)

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
  ## Atomically replace sorted existing pages, preserving physical-index and ordering refusal.
  ## Validate all membership and access before copying. Sparse replacement searches the
  ## affected slots, while dense replacement walks a monotone cursor. Copy the block
  ## reference root and each touched block once so unrelated page and chunk owners stay shared.
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
  if slots.rawData == nil or changed.rawData == nil:
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  cursor = 0
  for index in 0..<replacements.len:
    # Every input has passed; collect exact slots and new immutable byte owners only now.
    if sparse:
      cursor = lowerBound(data, uint32(replacements[index].index))
    else:
      while uint32(data.pages[cursor].index) < uint32(replacements[index].index): inc cursor
    slots.add(cursor)
    changed.add(pageFromReplacement(data.pages[cursor], replacements[index]))
    inc cursor
  var directory = default(PageDirectory)
  let replaced = replacedDirectory(data.pages, slots, changed, directory)
  if replaced != MachineError.None: return MachineResult[Memory](status: replaced)
  MachineResult[Memory](status: MachineError.None,
    completed: Memory(data: MemoryData(pages: move(directory), limit: data.limit)))

proc beginResidentReplacements*(source: Memory): ResidentReplacementBatch =
  ## Bind one unpublished prepared-frame observation to its immutable source owner.
  ResidentReplacementBatch(source: source, lastSlot: -1, slots: @[], changed: @[],
    status: (if source.data == nil: MachineError.InvalidOwner else: MachineError.None))

proc stageResidentPage*(batch: var ResidentReplacementBatch, slot: MemoryPageSlot,
    expected: PageDescription, bytes: openArray[byte]): MachineError =
  ## Stage a 4096-byte view for an existing writable slot whose description
  ## matches expected. Slots must increase strictly. A refusal is sticky and
  ## prevents finishResidentReplacements from publishing the batch.
  ## An unchanged page advances the slot without staging a replacement. If
  ## all eight spans changed, copy them into one backing for the first seven
  ## spans and a separate tail. Otherwise copy the changed chunks and retain
  ## the immutable owners of the unchanged bytes. The input borrow ends here.
  if batch.status != MachineError.None: return batch.status
  let data {.cursor.} = batch.source.data
  if data == nil:
    batch.status = MachineError.InvalidOwner
    return batch.status
  if uint64(slot) >= uint64(data.pages.len) or bytes.len != 4096:
    batch.status = MachineError.InvalidRange
    return batch.status
  let at = int(uint32(slot))
  if at <= batch.lastSlot:
    batch.status = MachineError.UnsortedPages
    return batch.status
  let previous {.cursor.} = data.pages[at]
  if previous.index != expected.index or previous.access != expected.access or
      previous.access != PageAccess.ReadWrite:
    batch.status = MachineError.InvalidRange
    return batch.status
  # The matched extent and eight fixed offsets prove every compared and copied span.
  var differences = 0'u8
  for chunk in 0..<8:
    if cmpMem(borrowPageChunk(previous, chunk), unsafeAddr bytes[chunk*512], 512) != 0:
      differences = differences or (1'u8 shl chunk)
  if differences != 0:
    let changed: nil PageData = PageData(index: previous.index, access: previous.access)
    if changed == nil:
      batch.status = MachineError.LimitExceeded
      return batch.status
    if differences == high(uint8):
      # Every old span has been superseded. Capture the complete borrowed page
      # with one backing and one tail, without retaining the old payload.
      let backing: nil PageBacking = PageBacking()
      let tail: nil PageChunk = PageChunk()
      if backing == nil or tail == nil:
        batch.status = MachineError.LimitExceeded
        return batch.status
      copyMem(addr backing.bytes[0], unsafeAddr bytes[0], 3584)
      copyMem(addr tail.bytes[0], unsafeAddr bytes[3584], 512)
      changed.backing = backing
      changed.chunks[7] = tail
    else:
      changed.backing = previous.backing
      for chunk in 0..<8:
        # Copy changed chunks and retain each unchanged effective span.
        if (differences and (1'u8 shl chunk)) != 0:
          let copied: nil PageChunk = PageChunk()
          if copied == nil:
            batch.status = MachineError.LimitExceeded
            return batch.status
          copyMem(addr copied.bytes[0], unsafeAddr bytes[chunk*512], 512)
          changed.chunks[chunk] = copied
        else:
          # An unchanged nil override still resolves through the retained backing.
          changed.chunks[chunk] = previous.chunks[chunk]
      dropCoveredBacking(changed)
    let past = batch.slots.len+1
    batch.slots.add(at)
    batch.changed.add(changed)
    if batch.slots.len != past or batch.changed.len != past:
      batch.status = MachineError.LimitExceeded
      return batch.status
  batch.lastSlot = at
  MachineError.None

proc finishResidentReplacements*(batch: ResidentReplacementBatch): MachineResult[Memory] =
  ## Publish one complete replacement directory after the whole batch succeeds.
  if batch.status != MachineError.None: return MachineResult[Memory](status: batch.status)
  if batch.changed.len == 0:
    return MachineResult[Memory](status: MachineError.None, completed: batch.source)
  let data {.cursor.} = batch.source.data
  if data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  var directory = default(PageDirectory)
  let replaced = replacedDirectory(data.pages, batch.slots, batch.changed, directory)
  if replaced != MachineError.None: return MachineResult[Memory](status: replaced)
  let owner: nil MemoryData = MemoryData(limit: data.limit)
  if owner == nil: return MachineResult[Memory](status: MachineError.LimitExceeded)
  owner.pages = move(directory)
  MachineResult[Memory](status: MachineError.None, completed: Memory(data: owner))

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
  if not dropped and start == data.pages.len:
    # Ordered endpoints imply stop == start: append new pages without rebuilding complete prefix blocks.
    var directory = appendedDirectory(data.pages, first, past, access, int(total))
    return MachineResult[Memory](status: MachineError.None,
      completed: Memory(data: MemoryData(pages: move(directory), limit: data.limit)))
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
  ## Check widths 1, 2, 4 and 8 against the low 32 bits of the address.
  ## Exclusive-end overflow is settled first: a present final page panics and an
  ## absent one faults at its aligned address. A nonwrapping access into the low
  ## 64 KiB panics before page lookup. For a crossing store, missing second-page
  ## presence precedes first-page write permission so retry observes the correct fault.
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
  ## Store the low little-endian bytes after validating every touched page.
  ## Cloning starts after preflight so a cross-page fault cannot publish even its
  ## first part. The completed snapshot shares all untouched pages with its source.
  let checked = scalarSpan[false, true](memory, address, width)
  if checked.error != MachineError.None: return failure[Memory, ScalarSpan](checked)
  if memory.data == nil: return MachineResult[Memory](status: MachineError.InvalidOwner)
  let data = memory.data
  let span = checked.value
  var slots = @[span.first]
  var changed = @[writablePageClone(data.pages[span.first], span.offset, span.firstCount)]
  if slots.len != 1 or changed.len != 1: return MachineResult[Memory](
      status: MachineError.LimitExceeded)
  setPageScalar(changed[0], span.offset, span.firstCount, uint64(value))
  if span.firstCount < span.count:
    # Both permissions were validated before either private write; a crossing clones its second page once.
    slots.add(span.last)
    changed.add(writablePageClone(data.pages[span.last], 0, span.count-span.firstCount))
    if slots.len != 2 or changed.len != 2: return MachineResult[Memory](
        status: MachineError.LimitExceeded)
    setPageScalar(changed[1], 0, span.count-span.firstCount, uint64(value) shr (8*span.firstCount))
  var directory = default(PageDirectory)
  let replaced = replacedDirectory(data.pages, slots, changed, directory)
  if replaced != MachineError.None: return MachineResult[Memory](status: replaced)
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

proc copyPageOut(page: PageData, offset: int, output: var openArray[byte], first, count: int)
    {.requires: offset >= 0 and offset < 4096 and count >= 1 and count <= 4096-offset and
      first >= 0 and first < output.len and count <= output.len-first.} =
  ## Copy immutable owned chunks into a fresh independent result; no source byte pointer escapes.
  var copied = 0
  while copied < count:
    # Each batch stays inside one512-byte source allocation and the already-sized destination.
    let position = offset+copied
    let within = position mod 512
    let batch = min(count-copied, 512-within)
    let source = borrowPageChunk(page, position div 512, within)
    copyMem(addr output[first+copied], source, batch)
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
    let target {.cursor.} = page.chunks[position div 512]
    assert target != nil # Every target span was cloned before the host operation's first write.
    copyMem(addr target.bytes[within], unsafeAddr input[first+copied], batch)
    copied += batch

proc copyReadableRange(data: MemoryData, address: MemoryAddress, output: var openArray[byte]) =
  ## Copy a preflighted interval of exactly output.len bytes from the immutable owner.
  let size = output.len
  if size == 0: return # Empty intervals never inspect or narrow their ignored pointer.
  var copied = 0
  var at = lowerBound(data, uint32(uint64(address) div 4096))
  while copied < size:
    # The preflight proved all addresses and native index conversions before allocation.
    let physical = uint64(address) + uint64(copied)
    let offset = int(physical mod 4096)
    let count = min(size - copied, 4096 - offset)
    copyPageOut(data.pages[at], offset, output, copied, count)
    copied += count
    inc at # Complete preflight proved each consecutive physical page occupies the next sorted slot.

proc readBytes*(memory: Memory, address: MemoryAddress, length: MemoryLength,
    limit: MemoryByteLimit): MachineResult[seq[byte]] =
  ## Copy a complete readable host range into independent bytes; failure never exposes a readable prefix.
  let checked = inspectRange(memory, address, length, limit, false)
  if checked.error != MachineError.None:
    # Preserve the exact local reason or first inaccessible page without publishing partial bytes.
    return failure[seq[byte], bool](checked)
  let data = memory.data
  if data == nil: return MachineResult[seq[byte]](status: MachineError.InvalidOwner)
  let size = int(uint64(length))
  var bytes = newSeq[byte](size)
  if bytes.len != size: return MachineResult[seq[byte]](status: MachineError.LimitExceeded)
  copyReadableRange(data, address, bytes)
  MachineResult[seq[byte]](status: MachineError.None, completed: move(bytes))

proc readBytesInto*(memory: Memory, address: MemoryAddress, output: var openArray[byte],
    limit: MemoryByteLimit): MachineResult[bool] =
  ## Copy a complete readable host range of output.len bytes into caller storage without allocating.
  ## Apply the same preflight as readBytes; every refusal leaves the entire output untouched.
  let checked = inspectRange(memory, address, MemoryLength(uint64(output.len)), limit, false)
  if checked.error != MachineError.None: return checked
  let data = memory.data
  if data == nil: return MachineResult[bool](status: MachineError.InvalidOwner)
  copyReadableRange(data, address, output)
  checked

proc writeCheckedRange[FromMemory: static[bool]](data: MemoryData,
    destination: MemoryAddress, size: int, bytes: openArray[byte],
    source: MemoryData, sourceAddress: MemoryAddress): MachineResult[Memory] =
  ## Stage each affected page and publish one immutable directory after filling every chunk.
  var sourceSlot = when FromMemory: lowerBound(source, uint32(uint64(sourceAddress) div 4096))
    else: 0
  var sourceOffset = when FromMemory: int(uint64(sourceAddress) mod 4096) else: 0
  var slots = newSeqOfCap[int](size div 4096+2)
  var changed = newSeqOfCap[PageData](size div 4096+2)
  if slots.rawData == nil or changed.rawData == nil:
    return MachineResult[Memory](status: MachineError.LimitExceeded)
  var copied = 0
  var at = lowerBound(data, uint32(uint64(destination) div 4096))
  while copied < size:
    # Preflight proved a nonwrapping readable/writable sequence; each page gets one private header.
    let physical = uint64(destination)+uint64(copied)
    let offset = int(physical mod 4096)
    let count = min(size-copied, 4096-offset)
    let previous {.cursor.} = data.pages[at]
    let page: nil PageData = PageData(index: previous.index, access: previous.access,
        backing: previous.backing, chunks: previous.chunks)
    if page == nil: return MachineResult[Memory](status: MachineError.AllocationRefused)
    let firstChunk = offset div 512
    let lastChunk = (offset+count-1) div 512
    for chunk in firstChunk..lastChunk:
      # Preserve untouched bytes in partially covered chunks before either copy path writes.
      let privateChunk: nil PageChunk = PageChunk()
      if privateChunk == nil: return MachineResult[Memory](status: MachineError.AllocationRefused)
      if offset > chunk*512 or offset+count < (chunk+1)*512:
        copyMem(addr privateChunk.bytes[0], borrowPageChunk(previous, chunk), 512)
      page.chunks[chunk] = privateChunk
    dropCoveredBacking(page)
    when FromMemory:
      # Zip disjoint immutable source spans with the already private destination chunks.
      var moved = 0
      while moved < count:
        # Each batch ends at the earlier chunk boundary, which also bounds page access.
        let destinationOffset = offset+moved
        let sourceWithin = sourceOffset mod 512
        let destinationWithin = destinationOffset mod 512
        let batch = min(count-moved, min(512-sourceWithin, 512-destinationWithin))
        let target {.cursor.} = page.chunks[destinationOffset div 512]
        if target == nil: return MachineResult[Memory](status: MachineError.AllocationRefused)
        let origin = borrowPageChunk(source.pages[sourceSlot], sourceOffset div 512, sourceWithin)
        copyMem(addr target.bytes[destinationWithin], origin, batch)
        moved += batch
        sourceOffset += batch
        if sourceOffset == 4096:
          # The next nonempty batch, if any, starts at the next proven source page.
          sourceOffset = 0
          inc sourceSlot
    else:
      copyPageIn(page, offset, bytes, copied, count)
    slots.add(at)
    changed.add(page)
    copied += count
    inc at
  var directory = default(PageDirectory)
  let replaced = replacedDirectory(data.pages, slots, changed, directory)
  if replaced != MachineError.None: return MachineResult[Memory](status: replaced)
  let captured: nil MemoryData = MemoryData(pages: move(directory), limit: data.limit)
  if captured == nil: return MachineResult[Memory](status: MachineError.AllocationRefused)
  MachineResult[Memory](status: MachineError.None, completed: Memory(data: captured))

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
  writeCheckedRange[false](data, address, input.len, input, data, address)

proc copyMemoryBytes*(source: Memory, sourceAddress: MemoryAddress, destination: Memory,
    destinationAddress: MemoryAddress, length: MemoryLength,
    limit: MemoryByteLimit): MachineResult[Memory] =
  ## Copy a natural range between immutable memories and return a new destination.
  ## Preflight both complete ranges before staging writes. Overlap reads the original source bytes.
  let readable = inspectRange(source, sourceAddress, length, limit, false)
  if readable.error != MachineError.None: return failure[Memory, bool](readable)
  let writable = inspectRange(destination, destinationAddress, length, limit, true)
  if writable.error != MachineError.None: return failure[Memory, bool](writable)
  if uint64(length) == 0:
    # Empty ranges preserve the destination owner and ignore both addresses.
    return MachineResult[Memory](status: MachineError.None, completed: destination)
  let input = source.data
  let output = destination.data
  if input == nil or output == nil:
    return MachineResult[Memory](status: MachineError.InvalidOwner)
  writeCheckedRange[true](output, destinationAddress, int(uint64(length)), [], input,
      sourceAddress)

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
    writer.pages[slot].zeroChunks = 0 # Every writable cached header starts without inherited zero claims.
  writer.pages[slot].chunks[chunk] = copiedPageChunk(writer.pages[slot], chunk)
  dropCoveredBacking(writer.pages[slot])
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

proc captureSnapshot(program: Program, memory: Memory, info: MachineInfo): MachineResult[Machine] =
  ## Install immutable children only after the result owner exists.
  let data: nil MachineData = MachineData(info: info)
  if data == nil: return MachineResult[Machine](status: MachineError.LimitExceeded)
  data.program = program
  data.memory = memory
  MachineResult[Machine](status: MachineError.None, completed: Machine(data: data))

proc captureMachine*(program: Program, memory: Memory, info: MachineInfo): MachineResult[Machine] =
  ## Capture trusted CPU values at a validated instruction boundary.
  ## The supplied paid-block flag is retained as an environment input. Standard JAM
  ## initialization derives that state separately.

  # Empty/default memory must be distinguished from a valid all-inaccessible memory snapshot.
  if memory.data == nil: return MachineResult[Machine](status: MachineError.InvalidOwner)
  if uint64(info.gasDeficit) != 0:
    # Negative balances are terminal state and cannot be captured as executable guest input.
    return MachineResult[Machine](status: MachineError.InvalidGasState)
  # Validate owner, address and opcode marker without reconstructing unused operands.
  if instructionOpcode(program, info.pc).error != ProgramError.None:
    return MachineResult[Machine](status: MachineError.InvalidProgram)
  captureSnapshot(program, memory, info)

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
  captureSnapshot(program, memory, info)

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
