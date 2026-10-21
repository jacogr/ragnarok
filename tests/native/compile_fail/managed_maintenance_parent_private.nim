# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge the exact canonical snapshot bound into an opaque maintenance request.
# @@Verification={"group":"privacy","expected":"parent"}
import ../../../src/app/disk_chain
let hidden = default(PreparedDiskMaintenance).parent
