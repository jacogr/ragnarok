# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Ordinary populated borrowed assignment must reject duplicated production mapping authority.
# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-bytes-initialize","expected":"'=dup' is not available for type <ResidentBytes>","rationale":"ResidentBytes carries actual first-RW mapping retirement authority; an ordinary borrowed initialize would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_bytes.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(source: ResidentBytes): ResidentBytes =
  ## The source remains live after ordinary initialization; last-use moves cannot satisfy this copy.
  var duplicate = source
  assert source.len == 4099
  move(duplicate)

var source = populatedResidentBytes()
var duplicate = borrowed(source)
assert source.len == 4099
assert duplicate.len == 4099
