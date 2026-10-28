# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: RepositoryGeneration but got: Gas", "early": ["disk.(confirmsCurrentDiskPublication,", "[3] expected: RepositoryGeneration but got: Gas"]}

## Gas allowances cannot substitute a confirmed native disk generation.
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/state/disk_store as state_disk_store
import ../../../src/codec/work_digest as codec_work_digest
var disk = default(DiskStateStore)
let publication = default(PreparedCurrentDiskPublication)
discard disk.confirmsCurrentDiskPublication(publication, Gas(1))
