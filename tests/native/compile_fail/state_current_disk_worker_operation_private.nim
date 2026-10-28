# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "operation"}

## Caller mutation cannot change payload selection or native borrowed publication authority.
import ../../../src/app/disk_worker as app_disk_worker
let worker = default(DiskPublicationWorker)
discard worker.operation
