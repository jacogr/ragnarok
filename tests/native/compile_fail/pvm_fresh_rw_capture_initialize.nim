# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary populated borrowed assignment must reject duplicated production mapping authority.

# @@Verification={"group":"ownership_compile","build_name":"pvm-fresh-rw-capture-initialize","expected":"'=dup' is not available for type <FreshRWCapture>","rationale":"FreshRWCapture carries actual first-RW mapping retirement authority; an ordinary borrowed initialize would produce independent destructors for one live mapping and leave Frame/native views dangling.","reference":"src/pvm/internal/resident_capture.nim"}
import std/assertions
import ../../../src/pvm/internal/[resident_bytes, resident_capture]
import ../../support/pvm_resident_owners

proc borrowed(source: FreshRWCapture): FreshRWCapture =
  ## The source remains live after ordinary initialization; last-use moves cannot satisfy this copy.
  var duplicate = source
  assert source.error == FreshRWStatus.Owned
  move(duplicate)

var source = populatedFreshRWCapture()
var duplicate = borrowed(source)
assert source.error == FreshRWStatus.Owned
assert duplicate.error == FreshRWStatus.Owned
