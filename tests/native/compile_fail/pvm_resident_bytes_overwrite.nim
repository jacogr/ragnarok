# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Ordinary populated borrowed assignment must reject duplicated production mapping authority.
# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-bytes-overwrite","expected":"'=dup' is not available for type <ResidentBytes>","rationale":"ResidentBytes carries actual first-RW mapping retirement authority; an ordinary borrowed overwrite would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_bytes.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(destination: var ResidentBytes, source: ResidentBytes) =
  ## Both owners are already populated; assignment must not duplicate the still-borrowed source.
  destination = source
  assert source.len == 4099

var source = populatedResidentBytes()
var destination = populatedResidentBytes()
borrowed(destination, source)
assert source.len == 4099
assert destination.len == 4099
