# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering rejects duplication of full-state writer lease and selected-file retirement.
# @@Verification={"group":"ownership_compile","build_name":"storage-full-paged-writer-copy","expected":"'=dup' is not available for type <FullPagedWriter>"}
import ../../../src/storage/full_paged_store
proc duplicate(source: FullPagedWriter): FullPagedWriter =
  ## Returning a borrowed writer would duplicate its native retirement authority.
  source
var original = default(FullPagedWriter)
var copied = duplicate(original)
discard original.opened
discard copied.close
