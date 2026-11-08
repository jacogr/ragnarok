# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual scratch heap ownership cannot be cloned through an ordinary dereference.

# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-scratch-initialize","expected":"'=dup' is not available for type <FlatMemoryScratchData>","rationale":"The actual ARC scratch payload owns resident mapping retirement authority; borrowed initialize would duplicate that owner even though reference handles themselves may alias.","reference":"src/pvm/internal/handler_stream.nim"}
import std/assertions
import ../../../src/pvm/machine
import ../../../src/pvm/internal/handler_stream
import ../../support/pvm_resident_frames

proc duplicate(source: FlatMemoryScratch) =
  ## Copy the real named heap payload, not its freely retained reference handle.
  var copied = source[]
  assert flatMemoryScratchPayload(source) == 2097152'u64
  discard addr copied

let source = populatedScratch()
duplicate(source)
assert flatMemoryScratchPayload(source) == 2097152'u64
