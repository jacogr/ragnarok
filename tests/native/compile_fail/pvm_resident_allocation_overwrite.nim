# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Ordinary populated borrowed assignment must reject duplicated production mapping authority.
# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-allocation-overwrite","expected":"'=dup' is not available for type <ResidentAllocationResult>","rationale":"ResidentAllocationResult carries actual first-RW mapping retirement authority; an ordinary borrowed overwrite would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_bytes.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(destination: var ResidentAllocationResult, source: ResidentAllocationResult) =
  ## Both owners are already populated; assignment must not duplicate the still-borrowed source.
  destination = source
  assert source.error == ResidentAllocationError.None

var source = populatedResidentAllocation()
var destination = populatedResidentAllocation()
borrowed(destination, source)
assert source.error == ResidentAllocationError.None
assert destination.error == ResidentAllocationError.None
