# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A passive retirement job cannot expose or forge the facade's private incarnation and manifest authority.
# @@Verification={"group":"privacy","expected":"owner"}
import ../../../src/state/disk_store
let job = default(PreparedPagedRetirement)
discard job.owner
