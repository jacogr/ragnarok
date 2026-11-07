# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Populated actual production owners for ordinary-assignment rejection witnesses; never executed.

import std/assertions
import ../../src/pvm/machine
import ../../src/pvm/internal/[resident_bytes, resident_capture]

proc populatedResidentBytes*(): ResidentBytes =
  ## One successful fresh mapping has real release authority before the attempted borrowed copy.
  var allocation = tryMapFreshZero(4099)
  assert allocation.error == ResidentAllocationError.None
  result = resident_bytes.takeOwned(allocation)
  assert result.len == 4099

proc populatedResidentAllocation*(): ResidentAllocationResult =
  ## The successful tagged result itself owns the mapping before extraction or destruction.
  result = tryMapFreshZero(4099)
  assert result.error == ResidentAllocationError.None

proc populatedRWStorage*(): RWStorage =
  ## The actual cold storage aggregate owns a mapped alternative, never an empty default witness.
  var owner = populatedResidentBytes()
  result = takeResident(owner)
  assert result.logicalBytes == 4099 and result.mappedBytes >= 4099

proc populatedFreshRWCapture*(): FreshRWCapture =
  ## Genuine initialized source provenance admits a fully constructed resource-bearing factory result.
  let regions = [InitializationRegion(first: PageIndex(32), past: PageIndex(288),
    access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: 0)]
  let input = captureInitializationMemory(regions, [], [], PageLimit(256))
  assert input.error == MachineError.None
  let memory = input.value
  let layout = memoryLayout(memory)
  assert layout.error == MachineError.None
  result = tryCaptureFreshZeroRW(memory, layout.value, 0, 256)
  assert result.error == FreshRWStatus.Owned
