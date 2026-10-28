# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native disk ownership cannot escape through a publicly mutable nested journal.
# @@Verification={"group":"privacy","expected":"journal"}
import ../../../src/state/disk_store as state_disk_store
var owner = default(DiskStateStore)
discard owner.journal
