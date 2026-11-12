# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject ordinary duplication of the actual frame's native image lease.

# @@Verification={"group":"ownership_compile","build_name":"pvm-auxiliary-lease-copy","expected":"'=dup' is not available for type <NativeAuxiliaryLease>","rationale":"Two frame leases could return the same executable image twice or unmap it while the other frame still holds installed handlers.","reference":"src/pvm/internal/native_pipeline.nim"}
import std/assertions
import ../../../src/pvm/internal/native_pipeline

proc duplicateLease(source: NativeAuxiliaryLease): NativeAuxiliaryLease =
  ## The source remains live after initialization, so an implicit move cannot satisfy this copy.
  var copied = source
  assert not source.ready
  move(copied)

let source = default(NativeAuxiliaryLease)
let copied = duplicateLease(source)
assert not source.ready and not copied.ready
