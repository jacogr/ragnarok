# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine fresh first-RW capture bound to immutable page provenance.
## Only whole known-zero pages may be skipped; unknown pages are copied completely before publication.

import std/assertions
import ../machine
import ./resident_bytes

const FreshRWZeroPageMinimum = 256 # Initial unmeasured1MiB selection bound, never a quota.

type
  FreshRWStatus* {.pure.} = enum
    Uninitialized, NotSelected, Owned, InvalidMemory, AllocationRefused
  FreshRWCapture* = object
    ## Only Owned contains storage; decline/failure/default alternatives carry no payload.
    case status: FreshRWStatus
    of Owned: completed: ResidentBytes
    else: discard

proc `=copy`*(destination: var FreshRWCapture, source: FreshRWCapture) {.error.}
  ## Directly reject copying the actual resource-bearing capture result.

proc `=dup`*(source: FreshRWCapture): FreshRWCapture {.error.}
  ## A successful capture cannot be duplicated through wrapper assignment.

proc `=wasMoved`*(captured: var FreshRWCapture) {.nodestroy, inline.} =
  ## Reset is also used before first assignment; never inspect an uninitialized success tag.
  captured.status = FreshRWStatus.Uninitialized

proc `=destroy`*(captured: FreshRWCapture) =
  ## Failed and declined alternatives have no mapping to retire.
  if captured.status == FreshRWStatus.Owned: `=destroy`(captured.completed)

func error*(captured: FreshRWCapture): FreshRWStatus =
  ## Read-only status cannot expose success storage.
  captured.status

proc takeOwned*(captured: var FreshRWCapture): ResidentBytes {.
    requires: captured.status == FreshRWStatus.Owned.} =
  ## Consume only fully initialized storage; default/failure extraction is invalid.
  result = move(captured.completed)
  captured = FreshRWCapture(status: FreshRWStatus.Uninitialized)

proc tryCaptureFreshZeroRW*(memory: Memory, descriptions: openArray[PageDescription],
    first, after: int): FreshRWCapture =
  ## Coordinates are checked against the actual immutable source; no caller zero/freshness promise exists.
  when not FreshRWProfileEnabled:
    # Preserve capped/hardened/custom/unsupported managed construction before any foreign operation.
    return FreshRWCapture(status: FreshRWStatus.NotSelected)
  else:
    # The range and narrowing checks precede every count, multiplication and page lookup.
    if first < 0 or after <= first or after > descriptions.len or
        uint64(descriptions.len) > uint64(high(uint32)):
      return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
    let pages = after-first
    if pages > high(int) div 4096:
      return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
    let count = memoryPageCount(memory)
    if count.error != MachineError.None or uint64(uint32(count.value)) != uint64(descriptions.len):
      return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
    var knownZeroPages = 0
    for slot in first..<after:
      # Verify exact RW identity and genuine adjacency before asking for its immutable provenance.
      let expected = descriptions[slot]
      if expected.access != PageAccess.ReadWrite:
        return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
      if slot > first and uint64(uint32(expected.index)) !=
          uint64(uint32(descriptions[slot-1].index))+1:
        return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
      let known = memoryPageIsKnownZero(memory, MemoryPageSlot(uint32(slot)), expected)
      if known.error != MachineError.None:
        return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
      if known.value and knownZeroPages < FreshRWZeroPageMinimum:
        # Saturate the selection count while continuing complete source validation.
        inc knownZeroPages
    if knownZeroPages < FreshRWZeroPageMinimum:
      return FreshRWCapture(status: FreshRWStatus.NotSelected)
    var allocation = tryMapFreshZero(pages*4096)
    if allocation.error == ResidentAllocationError.InvalidSize:
      return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
    if allocation.error != ResidentAllocationError.None:
      return FreshRWCapture(status: FreshRWStatus.AllocationRefused)
    var owner = resident_bytes.takeOwned(allocation)
    var view = borrowRW(owner)
    for slot in first..<after:
      # The same immutable source/descriptions bind both passes, without a mask vector or later opcode work.
      let expected = descriptions[slot]
      let known = memoryPageIsKnownZero(memory, MemoryPageSlot(uint32(slot)), expected)
      if known.error != MachineError.None:
        return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
      if not known.value:
        # Every unknown page includes all eight chunks, even if a subset has genuine zero provenance.
        let offset = (slot-first)*4096
        assert offset >= 0 and offset <= view.len-4096
        let copied = copyMemoryPage(memory, MemoryPageSlot(uint32(slot)),
          view.toOpenArray(offset, offset+4095))
        if copied.error != MachineError.None:
          return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
        let actual = copied.value
        if actual.index != expected.index or actual.access != expected.access:
          return FreshRWCapture(status: FreshRWStatus.InvalidMemory)
    # The constructing view dies here; only the exclusive completely initialized owner escapes.
    FreshRWCapture(status: FreshRWStatus.Owned, completed: move(owner))
