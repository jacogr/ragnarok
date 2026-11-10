# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary populated borrowed assignment must reject duplicated production mapping authority.

# @@Verification={"group":"ownership_compile","build_name":"pvm-rw-storage-initialize","expected":"'=dup' is not available for type <RWStorage>","rationale":"RWStorage carries actual first-RW mapping retirement authority; an ordinary borrowed initialize would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_bytes.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(source: RWStorage): RWStorage =
  ## The source remains live after ordinary initialization; last-use moves cannot satisfy this copy.
  var duplicate = source
  assert source.logicalBytes == 4099
  move(duplicate)

var source = populatedRWStorage()
var duplicate = borrowed(source)
assert source.logicalBytes == 4099
assert duplicate.logicalBytes == 4099
