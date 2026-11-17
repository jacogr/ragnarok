# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive first-RW storage and one backend-neutral borrowed view.
## Foreign bytes are owner-accounted separately from managed heap telemetry; no quota or pool.
## Scalar transfers prove their full borrowed extent and preserve outputs/bytes on refusal.

import std/assertions

const FreshRWProfileEnabled* = defined(nimNativeAlloc) and sizeof(int) == 8 and
  (defined(linux) or defined(macosx)) and not defined(nimMaxHeap) and
  not defined(nimHardenOutOfMem) and not defined(useMimalloc) and
  not defined(useLibc) and not defined(nimNoLibc)

when FreshRWProfileEnabled:
  # Ineligible profiles do not even bind the mapping header into generated code.
  const ResidentHeader = "${path}/resident_os.h"
  type RawAllocation {.importc: "pvm_resident_allocation", header: ResidentHeader,
      bycopy.} = object
    data: nil pointer
    logical, backing: csize_t
    status: cint
  proc rawMap(logical: csize_t): RawAllocation {.
    cdecl, importc: "pvm_resident_map", header: ResidentHeader.}
    ## The C boundary owns actual platform constants and checked host-page rounding.
  proc rawUnmap(data: pointer, backing: csize_t) {.
    cdecl, importc: "pvm_resident_unmap", header: ResidentHeader.}
    ## Exact whole-map release finishes before owner accounting can disappear.

type
  ResidentBytes* = object
    ## Exclusive mapping authority; logical/backing extents follow active and idle ownership.
    data: nil pointer
    logical, backing: csize_t
  RWView* = object
    ## Plain synchronous borrow: intended length-first16-byte shape, requiring lowering proof.
    length: int
    data: nil ptr UncheckedArray[byte]
  RWSpanKind {.pure.} = enum
    ## Default spans are genuinely empty; present spans carry a proven non-null address and complete count.
    Empty, Present
  RWSpan* = object
    ## Checked synchronous array capability; its original RW owner must remain stable throughout use.
    ## The empty alternative owns no address. Present fields are private and constructed only by checked slicing.
    case kind: RWSpanKind
    of Present:
      count: int
      data: ptr UncheckedArray[byte]
    of Empty:
      empty: array[0, byte]
  RWByteAddress = nil ptr byte
    ## Plain pointer output for checked native descriptors; it grants no lifetime beyond the retained RW owner.
  RWStorageKind {.pure.} = enum
    Empty, Managed, Resident
  RWStorage* = object
    ## Cold exclusive alternatives provide the same stable view without per-operation tag tests.
    case kind: RWStorageKind
    of Managed: managed: seq[byte]
    of Resident: resident: ResidentBytes
    of Empty: discard
  ResidentAllocationError* {.pure.} = enum
    Uninitialized, None, InvalidSize, AllocationRefused
  ResidentAllocationResult* = object
    ## Failed/default results have a reason only; successful storage is consumed explicitly.
    case status: ResidentAllocationError
    of None: completed: ResidentBytes
    else: discard

when defined(pvmResidentWitness):
  # Test-only single-thread observations never become a production ledger or admission framework.
  type ResidentWitnessSnapshot* = object
    ## Exact successful maps/releases and live full extents, separate from managed ARC/RSS.
    acquisitions*, releases*, refusals*, logicalBytes*, mappedBytes*: uint64
  var witnessSnapshot {.threadvar.}: ResidentWitnessSnapshot
  var witnessRefuseNext {.threadvar.}: bool

  proc residentWitnessSnapshot*(): ResidentWitnessSnapshot =
    ## Read primitive observations before allocating/printing diagnostics.
    witnessSnapshot

  proc refuseNextResidentAllocation*() =
    ## One selected request fails locally; declining the foreign factory does not consume it.
    witnessRefuseNext = true

proc `=copy`*(destination: var ResidentBytes, source: ResidentBytes) {.error.}
  ## Ordinary borrowed copies cannot duplicate raw release authority.

proc `=dup`*(source: ResidentBytes): ResidentBytes {.error.}
  ## Independent duplication refusal applies in every interpreter/JIT profile.

proc `=wasMoved`*(owner: var ResidentBytes) {.nodestroy, inline.} =
  ## Disarm the source without retiring the destination's transferred extent.
  owner.data = nil
  owner.logical = 0
  owner.backing = 0

proc `=destroy`*(owner: ResidentBytes) =
  ## Default, failed and moved owners release nothing; live owners release exactly once.
  let data = owner.data
  if data != nil:
    when FreshRWProfileEnabled:
      when defined(pvmResidentWitness):
        # Validate a real single-thread live charge before touching its backing.
        assert witnessSnapshot.acquisitions > witnessSnapshot.releases
        assert uint64(owner.logical) <= witnessSnapshot.logicalBytes
        assert uint64(owner.backing) <= witnessSnapshot.mappedBytes
      # The private OS routine treats a release failure as fatal, never a successful retirement.
      rawUnmap(data, owner.backing)
      when defined(pvmResidentWitness):
        # Retirement is observed only after successful exact-span release.
        inc witnessSnapshot.releases
        witnessSnapshot.logicalBytes -= uint64(owner.logical)
        witnessSnapshot.mappedBytes -= uint64(owner.backing)
    else:
      # This compile profile cannot construct a foreign owner.
      assert false

proc `=copy`*(destination: var RWStorage, source: RWStorage) {.error.}
  ## The actual tagged aggregate is directly noncopyable, independently of its child hooks.

proc `=dup`*(source: RWStorage): RWStorage {.error.}
  ## Neither managed payload cloning nor raw foreign duplication is implicit.

proc `=wasMoved`*(storage: var RWStorage) {.nodestroy, inline.} =
  ## Fresh locals may be uninitialized; close ownership without inspecting the old tag or payload.
  storage.kind = RWStorageKind.Empty

proc `=destroy`*(storage: RWStorage) =
  ## Exactly the selected live child owns bytes; no inactive variant is read.
  case storage.kind
  of RWStorageKind.Managed: `=destroy`(storage.managed)
  of RWStorageKind.Resident: `=destroy`(storage.resident)
  of RWStorageKind.Empty: discard # Default and moved alternatives own nothing.

proc `=copy`*(destination: var ResidentAllocationResult,
    source: ResidentAllocationResult) {.error.}
  ## Success authority cannot be copied through a result wrapper.

proc `=dup`*(source: ResidentAllocationResult): ResidentAllocationResult {.error.}
  ## Refuse duplication on the actual result carrier as well as its owner child.

proc `=wasMoved`*(allocation: var ResidentAllocationResult) {.nodestroy, inline.} =
  ## This also initializes fresh result storage; a closed tag grants no payload authority.
  allocation.status = ResidentAllocationError.Uninitialized

proc `=destroy`*(allocation: ResidentAllocationResult) =
  ## Reason-only alternatives carry no resource.
  if allocation.status == ResidentAllocationError.None:
    `=destroy`(allocation.completed)

func error*(allocation: ResidentAllocationResult): ResidentAllocationError =
  ## Read status without exposing or copying success storage.
  allocation.status

proc tryMapFreshZero*(bytes: int): ResidentAllocationResult =
  ## Internal factory primitive; profile ineligibility is handled before this function is called.
  if bytes < 0 or uint64(bytes) > uint64(high(csize_t)):
    return ResidentAllocationResult(status: ResidentAllocationError.InvalidSize)
  when FreshRWProfileEnabled:
    when defined(pvmResidentWitness):
      if bytes > 0 and witnessRefuseNext:
        # Exercise actual selected-allocation error plumbing without an OS-dependent exhaustion size.
        witnessRefuseNext = false
        assert witnessSnapshot.refusals < high(uint64)
        inc witnessSnapshot.refusals
        return ResidentAllocationResult(status: ResidentAllocationError.AllocationRefused)
    # A real selected OS refusal never triggers a retry through managed storage.
    let raw = rawMap(csize_t(bytes))
    if raw.status == 1:
      return ResidentAllocationResult(status: ResidentAllocationError.InvalidSize)
    if raw.status != 0:
      when defined(pvmResidentWitness):
        # OS/query refusal remains distinct from a bad-size preflight.
        assert witnessSnapshot.refusals < high(uint64)
        inc witnessSnapshot.refusals
      return ResidentAllocationResult(status: ResidentAllocationError.AllocationRefused)
    assert raw.logical == csize_t(bytes) and raw.backing >= raw.logical
    assert (bytes == 0 and raw.data == nil and raw.backing == 0) or
      (bytes > 0 and raw.data != nil)
    when defined(pvmResidentWitness):
      if bytes > 0:
        # Exact full logical/backing observations never discount untouched or idle zero pages.
        assert witnessSnapshot.acquisitions < high(uint64)
        assert uint64(raw.logical) <= high(uint64)-witnessSnapshot.logicalBytes
        assert uint64(raw.backing) <= high(uint64)-witnessSnapshot.mappedBytes
        inc witnessSnapshot.acquisitions
        witnessSnapshot.logicalBytes += uint64(raw.logical)
        witnessSnapshot.mappedBytes += uint64(raw.backing)
    ResidentAllocationResult(status: ResidentAllocationError.None,
      completed: ResidentBytes(data: raw.data, logical: raw.logical, backing: raw.backing))
  else:
    # Factory selection must return NotSelected earlier; no OS allocation exists in this arm.
    ResidentAllocationResult(status: ResidentAllocationError.AllocationRefused)

proc takeOwned*(allocation: var ResidentAllocationResult): ResidentBytes {.
    requires: allocation.status == ResidentAllocationError.None.} =
  ## Consume exactly one success; a repeated extraction has no valid success contract.
  result = move(allocation.completed)
  allocation = ResidentAllocationResult(status: ResidentAllocationError.Uninitialized)

func initRWStorage*(): RWStorage =
  ## Explicitly construct the genuine empty alternative when nested in another owning constructor.
  RWStorage(kind: RWStorageKind.Empty)

proc takeManaged*(bytes: var seq[byte]): RWStorage =
  ## Transfer legacy storage without a clone or foreign allocation.
  RWStorage(kind: RWStorageKind.Managed, managed: move(bytes))

proc takeResident*(bytes: var ResidentBytes): RWStorage =
  ## Transfer the completed foreign owner and its complete logical/backing charge.
  RWStorage(kind: RWStorageKind.Resident, resident: move(bytes))

proc tryBorrowRW*(owner: var ResidentBytes, view: var RWView): bool =
  ## Validate complete owner extents before exposing a synchronous view; refusal leaves output and owner unchanged.
  if owner.logical > csize_t(high(int)) or owner.backing < owner.logical: return false
  if owner.logical == 0:
    if owner.data != nil or owner.backing != 0: return false
    view = default(RWView)
    return true
  let data = owner.data
  if data == nil: return false
  view = RWView(length: int(owner.logical), data: cast[ptr UncheckedArray[byte]](data))
  true

proc tryBorrowRW*(storage: var RWStorage, view: var RWView): bool =
  ## Select the final installed owner once; a failed selection cannot publish an empty replacement view.
  case storage.kind
  of RWStorageKind.Managed:
    if storage.managed.len == 0:
      view = default(RWView)
      return true
    let data = storage.managed.rawData
    if data == nil: return false
    view = RWView(length: storage.managed.len, data: data)
    true
  of RWStorageKind.Resident:
    tryBorrowRW(storage.resident, view)
  of RWStorageKind.Empty:
    view = default(RWView)
    true

func len*(view: RWView): int =
  ## Hot access is independent of the storage alternative.
  view.length

func len*(owner: ResidentBytes): int =
  ## Observe the complete logical extent without borrowing a mutable payload view.
  int(owner.logical)

func len*(storage: RWStorage): int =
  ## Cold accounting observes complete payload, including demand-zero pages.
  case storage.kind
  of RWStorageKind.Managed: storage.managed.len
  of RWStorageKind.Resident: int(storage.resident.logical)
  of RWStorageKind.Empty: 0 # Default/moved storage has no logical charge.

func logicalBytes*(storage: RWStorage): uint64 =
  ## Both backings count their full logical bytes in existing retention policy.
  uint64(storage.len)

func mappedBytes*(storage: RWStorage): uint64 =
  ## Only actual foreign mapping spans are known here; this is neither managed overhead nor RSS.
  case storage.kind
  of RWStorageKind.Resident: uint64(storage.resident.backing)
  of RWStorageKind.Managed, RWStorageKind.Empty: 0'u64 # Managed telemetry remains separate.

when defined(pvmSharedAsyncWitness):
  proc invalidateRWDataForWitness*(view: var RWView) =
    ## Drop only a test borrow's data pointer; its real owner remains live for independent byte checks.
    view.data = nil

func containsSpan*(view: RWView, first, count: int): bool {.inline.} =
  ## Prove a nonempty synchronous extent without reading bytes or granting ownership.
  first >= 0 and count > 0 and view.length >= count and first <= view.length-count and
    view.data != nil

func tryReadScalar*[W: static[int]](view: RWView, at: int, value: var uint64): bool {.inline.} =
  ## Read exactly one little-endian scalar from this synchronous borrow. A missing pointer or
  ## incomplete extent returns false without changing value. The owner must remain stable/alive
  ## for the call. No pointer or mutable storage escapes, and no allocation is performed.
  when W != 1 and W != 2 and W != 4 and W != 8: {.error: "RW scalar transfers require 1, 2, 4, or 8 bytes".}
  if at < 0 or view.length < W or at > view.length-W: return false
  let data = view.data
  if data == nil: return false
  var word = 0'u64
  var endian = 1'u16
  var tag = default(array[2, byte])
  copyMem(addr tag[0], addr endian, 2)
  if tag[0] == 1:
    # The complete bounds proof precedes the unaligned transfer into a disjoint private word.
    copyMem(addr word, unsafeAddr data[at], W)
  else:
    # Other host byte orders retain the original scalar little-endian equation.
    for index in 0..<W: word = word or (uint64(data[at+index]) shl (index*8))
  value = word
  true

proc tryWriteScalar*[W: static[int]](view: var RWView, at: int, value: uint64): bool {.inline.} =
  ## Write one truncated little-endian scalar only after its complete synchronous borrow is
  ## proved. False leaves every byte untouched; neither allocation nor resize authority exists.
  when W != 1 and W != 2 and W != 4 and W != 8: {.error: "RW scalar transfers require 1, 2, 4, or 8 bytes".}
  if at < 0 or view.length < W or at > view.length-W: return false
  var data = view.data
  if data == nil: return false
  var endian = 1'u16
  var tag = default(array[2, byte])
  copyMem(addr tag[0], addr endian, 2)
  if tag[0] == 1:
    # All software failure checks finish before the first mutable byte is exposed.
    var word = value
    copyMem(addr data[at], addr word, W)
  else:
    # Portable hosts store the same low bytes without reinterpreting native byte order.
    for index in 0..<W: data[at+index] = byte((value shr (index*8)) and 255)
  true

when defined(pvmResidentWitness):
  proc residentWitnessNullScalar*(): bool =
    ## A forged test-only nonempty/no-data view must refuse without dereferencing or changing output.
    var view = RWView(length: 8, data: nil)
    var value = 0xfedcba9876543210'u64
    if tryReadScalar[1](view, 0, value) or tryReadScalar[2](view, 0, value) or
        tryReadScalar[4](view, 0, value) or tryReadScalar[8](view, 0, value): return false
    if value != 0xfedcba9876543210'u64: return false
    not (tryWriteScalar[1](view, 0, 1) or tryWriteScalar[2](view, 0, 1) or
      tryWriteScalar[4](view, 0, 1) or tryWriteScalar[8](view, 0, 1))

func tryBorrowedData*(view: RWView, first, count: int, data: var RWByteAddress): bool {.inline.} =
  ## Prove the whole requested native/copy span before exposing its address; refusal preserves output.
  ## Empty success carries no address, and no borrowed pointer may outlive the unchanged installed RW owner.
  if view.length < 0 or first < 0 or count < 0 or first > view.length or count > view.length-first:
    return false
  let source = view.data
  if view.length > 0 and source == nil: return false
  if count == 0:
    data = nil
    return true
  if source == nil: return false
  data = unsafeAddr source[first]
  true

func tryBorrowRWSpan*(view: RWView, first, count: int, span: var RWSpan): bool {.inline.} =
  ## Construct a checked array capability only after complete range/owner validation; refusal preserves output.
  var data: RWByteAddress = nil
  if not tryBorrowedData(view, first, count, data): return false
  if count == 0:
    span = default(RWSpan)
    return true
  if data == nil: return false
  span = RWSpan(kind: RWSpanKind.Present, count: count,
    data: cast[ptr UncheckedArray[byte]](data))
  true

func toOpenArray*(span: var RWSpan): openArray[byte] =
  ## Use the checked complete extent synchronously. The mutable span binds the returned array's short lifetime.
  ## Empty spans convert through their actual zero-length member, without a nil-to-nonnull cast or borrowed temporary.
  case span.kind
  of RWSpanKind.Empty: toOpenArray(span.empty)
  of RWSpanKind.Present: toOpenArray(span.data, 0, span.count-1)

when defined(pvmResidentWitness) or defined(pvmSharedAsyncWitness) or
    defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness) or defined(pvmPaidMixedLoopWitness):
  proc borrowRW*(owner: var ResidentBytes): RWView =
    ## Asserted convenience for test fixtures only; production must handle explicit borrowing refusal.
    result = default(RWView)
    assert tryBorrowRW(owner, result)

  proc borrowRW*(storage: var RWStorage): RWView =
    ## Preserve concise actual-owner test fixtures without providing a production infallible constructor.
    result = default(RWView)
    assert tryBorrowRW(storage, result)

  func `[]`*(view: RWView, index: int): byte =
    ## Only tests require an asserted byte observation; ordinary execution uses fallible scalar transfers.
    var word = 0'u64
    assert tryReadScalar[1](view, index, word)
    byte(word)

  proc `[]=`*(view: var RWView, index: int, value: byte) =
    ## Test setup writes still exercise the actual complete production scalar guard.
    assert tryWriteScalar[1](view, index, uint64(value))

  func toOpenArray*(view: RWView, first, last: int): openArray[byte] =
    ## Test-only legacy slice convenience; checked production slices use RWSpan.
    assert first >= 0 and first <= last and last < view.length and view.data != nil
    toOpenArray(view.data, first, last)

when defined(pvmResidentWitness) or defined(pvmSharedAsyncWitness):
  proc writeRWSpanForWitness(bytes: var openArray[byte]) =
    ## The real checked span must support mutable consumers; empty spans perform no write.
    if bytes.len > 0: bytes[0] = 0xa5

  proc probeRWViewRefusals*(): bool =
    ## Real managed ownership proves complete range checks, unchanged outputs, aliasing and true empty capabilities.
    var bytes = @[0x11'u8, 0x22, 0x33, 0x44]
    var storage = takeManaged(bytes)
    var view = default(RWView)
    if not tryBorrowRW(storage, view) or view.len != 4: return false
    var address: RWByteAddress = nil
    if not tryBorrowedData(view, 0, 4, address) or address == nil: return false
    let original = address
    var span = default(RWSpan)
    if not tryBorrowRWSpan(view, 1, 2, span): return false
    let saved = span
    for bounds in [(-1, 1), (0, -1), (4, 1), (high(int), 1), (1, high(int))]:
      # Every refused request preserves the last valid address/span rather than substituting an empty window.
      if tryBorrowedData(view, bounds[0], bounds[1], address) or address != original: return false
      if tryBorrowRWSpan(view, bounds[0], bounds[1], span) or span != saved: return false
    writeRWSpanForWitness(span.toOpenArray)
    var word = 0'u64
    if not tryReadScalar[4](view, 0, word) or word != 0x4433a511'u64: return false
    for broken in [RWView(length: 4, data: nil), RWView(length: -1, data: view.data)]:
      if tryBorrowedData(broken, 0, 1, address) or address != original: return false
      if tryBorrowRWSpan(broken, 0, 1, span) or span != saved: return false
    var owner = default(ResidentBytes)
    owner.logical = csize_t(high(int))+1
    if tryBorrowRW(owner, view) or view.len != 4: return false
    owner.logical = 1
    owner.backing = 1
    if tryBorrowRW(owner, view) or view.len != 4: return false
    owner.logical = 0
    owner.backing = 0
    if not tryBorrowRW(owner, view) or view.len != 0: return false
    if not tryBorrowRWSpan(view, 0, 0, span): return false
    if span.toOpenArray.len != 0: return false
    writeRWSpanForWitness(span.toOpenArray)
    if not tryBorrowedData(view, 0, 0, address) or address != nil: return false
    var intact = default(RWView)
    if not tryBorrowRW(storage, intact): return false
    tryReadScalar[4](intact, 0, word) and word == 0x4433a511'u64

when defined(pvmResidentWitness):
  proc residentWitnessLayout*(): array[7, int] =
    ## Inspect actual private field addresses only after all owning hooks are bound.
    var owner = default(ResidentBytes)
    var view = default(RWView)
    let ownerBase = cast[uint](addr owner)
    let viewBase = cast[uint](addr view)
    [sizeof(ResidentBytes), sizeof(RWView), sizeof(RWStorage),
      int(cast[uint](addr owner.logical)-ownerBase),
      int(cast[uint](addr owner.backing)-ownerBase),
      int(cast[uint](addr view.length)-viewBase),
      int(cast[uint](addr view.data)-viewBase)]
