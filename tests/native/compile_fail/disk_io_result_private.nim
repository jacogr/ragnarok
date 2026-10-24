# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native ownership and successful facade payloads cannot be forged through private backing fields.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/state/disk_store
var outcome = default(DiskIoResult[bool])
outcome.completed = true
