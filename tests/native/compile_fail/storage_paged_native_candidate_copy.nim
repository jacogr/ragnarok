# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering must reject duplication of the explicit-close candidate owner.
# @@Verification={"group":"ownership_compile","build_name":"storage-paged-native-candidate-copy","expected":"'=dup' is not available for type <PagedCandidate>"}
import ../../../src/storage/paged_store as storage_paged_store
proc duplicate(source: PagedCandidate): PagedCandidate =
  ## Returning a borrowed owner would duplicate native retirement authority.
  source
var original = default(PagedCandidate)
var copied = duplicate(original)
discard original.opened
discard copied.close
