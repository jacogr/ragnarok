# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A default/full completion cannot expose an unselected light publication snapshot.
# @@Verification={"group":"privacy","expected":"lightOutcome"}
import ../../../src/app/disk_worker as app_disk_worker
let completion = default(DiskPublicationCompletion)
discard completion.lightOutcome
