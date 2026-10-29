# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering rejects duplication of an explicitly retired full-state reader pin.
# @@Verification={"group":"ownership_compile","build_name":"storage-full-paged-reader-copy","expected":"'=dup' is not available for type <FullPagedReader>"}
import ../../../src/storage/full/paged/store as full_paged_store
proc duplicate(source: FullPagedReader): FullPagedReader =
  ## Returning a borrowed owner would duplicate native descriptor retirement authority.
  source
var original = default(FullPagedReader)
var copied = duplicate(original)
discard original.opened
discard copied.close
