# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native ownership and successful facade payloads cannot be forged through private backing fields.
# @@Verification={"group":"privacy","expected":"paged"}
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/full_paged_store as storage_full_paged_store
var disk = default(DiskStateStore)
disk.paged = default(FullPagedWriter)
