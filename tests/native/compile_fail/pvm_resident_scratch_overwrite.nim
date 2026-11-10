# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual scratch heap ownership cannot be cloned through an ordinary dereference.

# @@Verification={"group":"ownership_compile","build_name":"pvm-resident-scratch-overwrite","expected":"'=dup' is not available for type <FlatMemoryScratchData>","rationale":"The actual ARC scratch payload owns resident mapping retirement authority; borrowed overwrite would duplicate that owner even though reference handles themselves may alias.","reference":"src/pvm/internal/handler_stream.nim"}
import std/assertions
import ../../../src/pvm/machine
import ../../../src/pvm/internal/handler_stream
import ../../support/pvm_resident_frames

proc overwrite(destination, source: FlatMemoryScratch) =
  ## Both actual heap cells remain live after the attempted payload overwrite.
  destination[] = source[]
  assert flatMemoryScratchPayload(source) == 2097152'u64
  assert flatMemoryScratchPayload(destination) == 2097152'u64

let source = populatedScratch()
let destination = populatedScratch()
overwrite(destination, source)
assert flatMemoryScratchPayload(source) == 2097152'u64
