# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering must reject duplication of the explicit-close writer owner.
# @@Verification={"group":"ownership_compile","build_name":"storage-paged-native-writer-copy","expected":"'=dup' is not available for type <PagedWriter>"}
import ../../../src/storage/paged_store as storage_paged_store
proc duplicate(source: PagedWriter): PagedWriter =
  ## Returning a borrowed owner would duplicate native retirement authority.
  source
var original = default(PagedWriter)
var copied = duplicate(original)
discard original.opened
discard copied.close
