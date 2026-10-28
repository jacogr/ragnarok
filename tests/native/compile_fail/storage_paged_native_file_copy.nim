# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering must reject duplication of the explicit-close file owner.
# @@Verification={"group":"ownership_compile","build_name":"storage-paged-native-file-copy","expected":"'=dup' is not available for type <PagedFile>"}
import ../../../src/storage/paged_io as storage_paged_io
proc duplicate(source: PagedFile): PagedFile =
  ## Returning a borrowed owner would duplicate native retirement authority.
  source
var original = default(PagedFile)
var copied = duplicate(original)
discard original.opened
discard copied.close
