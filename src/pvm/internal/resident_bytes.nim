# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive first-RW storage and one backend-neutral borrowed view.
## Foreign bytes are owner-accounted separately from managed heap telemetry; no quota or pool.

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

proc borrowRW*(owner: var ResidentBytes): RWView =
  ## Construction may borrow before storage installation; no borrow may outlive this owner.
  assert owner.logical <= csize_t(high(int))
  assert owner.logical == 0 or owner.data != nil
  RWView(length: int(owner.logical),
    data: cast[nil ptr UncheckedArray[byte]](owner.data))

proc borrowRW*(storage: var RWStorage): RWView =
  ## Select the backing once at installation, after final owner transfer.
  case storage.kind
  of RWStorageKind.Managed:
    # Empty managed storage has no element0 address.
    if storage.managed.len == 0: return default(RWView)
    RWView(length: storage.managed.len,
      data: cast[ptr UncheckedArray[byte]](addr storage.managed[0]))
  of RWStorageKind.Resident:
    borrowRW(storage.resident)
  of RWStorageKind.Empty:
    default(RWView) # No owner means no visible extent or usable pointer.

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

func `[]`*(view: RWView, index: int): byte =
  ## Read one checked byte; mutations go through the separate checked setter.
  assert index >= 0 and index < view.length and view.data != nil
  view.data[index]

proc `[]=`*(view: var RWView, index: int, value: byte) =
  ## Stores change bytes without owner/tag checks or resize authority.
  assert index >= 0 and index < view.length and view.data != nil
  view.data[index] = value

proc borrowedData*(view: RWView): nil ptr byte =
  ## Only synchronous descriptor builders may retain this pointer inside the active Frame.
  assert view.length >= 0 and (view.length == 0 or view.data != nil)
  cast[nil ptr byte](view.data)

func toOpenArray*(view: RWView, first, last: int): openArray[byte] {.inline.} =
  ## Nonempty scoped slice; callers guard empty descriptors before requesting an array view.
  assert first >= 0 and first <= last and last < view.length and view.data != nil
  toOpenArray(view.data, first, last)

proc borrowedData*(view: RWView, index: int): ptr byte =
  ## Borrow one checked location for synchronous native descriptors or copies inside the active Frame.
  unsafeAddr view.toOpenArray(index, index)[0]

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
