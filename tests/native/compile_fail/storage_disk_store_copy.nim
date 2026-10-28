# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copying the composite disk state and journal owner must fail actual ARC lowering.
# @@Verification={"group":"ownership_compile","build_name":"disk-store-copy","expected":"'=dup' is not available for type <DiskStateStore>"}
import ../../../src/state/disk_store as state_disk_store
proc duplicated(source: DiskStateStore): DiskStateStore =
  ## Returning a borrowed owner requires prohibited descriptor duplication.
  source
var first = default(DiskStateStore)
var second = duplicated(first)
discard first.opened
discard second.close
