# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary populated borrowed assignment must reject duplicated production mapping authority.

# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-allocation-initialize","expected":"'=dup' is not available for type <ResidentAllocationResult>","rationale":"ResidentAllocationResult carries actual first-RW mapping retirement authority; an ordinary borrowed initialize would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_bytes.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(source: ResidentAllocationResult): ResidentAllocationResult =
  ## The source remains live after ordinary initialization; last-use moves cannot satisfy this copy.
  var duplicate = source
  assert source.error == ResidentAllocationError.None
  move(duplicate)

var source = populatedResidentAllocation()
var duplicate = borrowed(source)
assert source.error == ResidentAllocationError.None
assert duplicate.error == ResidentAllocationError.None
