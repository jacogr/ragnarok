# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native ownership and successful facade payloads cannot be forged through private backing fields.
# @@Verification={"group":"privacy","expected":"paged"}
import ../../../src/state/disk_store
import ../../../src/storage/full/paged/store as full_paged_store
var disk = default(DiskStateStore)
disk.paged = default(FullPagedWriter)
