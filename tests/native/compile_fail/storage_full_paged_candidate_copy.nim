# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering rejects duplication of a full-state sealed candidate descriptor/capability.
# @@Verification={"group":"ownership_compile","build_name":"storage-full-paged-candidate-copy","expected":"'=dup' is not available for type <FullPagedCandidate>","rationale":"A sealed full-state candidate owns authoring, publication and cleanup authority; returning a borrowed copy could publish or retire the same candidate twice.","reference":"src/storage/full/paged/store.nim"}
import ../../../src/storage/full/paged/store as full_paged_store
proc duplicate(source: FullPagedCandidate): FullPagedCandidate =
  ## Returning a borrowed candidate would duplicate authoring and retirement authority.
  source
var original = default(FullPagedCandidate)
var copied = duplicate(original)
discard original.opened
discard copied.close
