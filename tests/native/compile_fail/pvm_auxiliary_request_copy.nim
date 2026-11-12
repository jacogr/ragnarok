# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject ordinary duplication of the actual host-owned typed request.

# @@Verification={"group":"ownership_compile","build_name":"pvm-auxiliary-request-copy","expected":"'=dup' is not available for type <NativeAuxiliaryRequest>","rationale":"The immutable heterogeneous request owns its loop and Read payloads through worker copy and physical retirement. Duplicating the handle would split host collection authority.","reference":"src/pvm/internal/native_auxiliary.nim"}
import std/assertions
import ../../../src/pvm/internal/native_auxiliary

proc duplicateRequest(source: NativeAuxiliaryRequest): NativeAuxiliaryRequest =
  ## The source remains live after initialization, so an implicit move cannot satisfy this copy.
  var copied = source
  assert source.isEmpty
  move(copied)

let source = default(NativeAuxiliaryRequest)
let copied = duplicateRequest(source)
assert source.isEmpty and copied.isEmpty
