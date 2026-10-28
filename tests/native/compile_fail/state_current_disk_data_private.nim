# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Callers cannot fabricate retained current disk publication authority.
import ../../../src/app/disk_chain as app_disk_chain
let publication = default(PreparedCurrentDiskPublication)
discard publication.data
