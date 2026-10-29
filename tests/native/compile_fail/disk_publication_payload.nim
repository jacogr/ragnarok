# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached callers cannot forge a prepared disk publication or replace its bound context.
# @@Verification={"group":"privacy","expected":"context"}
import ../../../src/app/disk/chain as disk_chain
var publication = default(PreparedDiskPublication)
publication.context = @[1'u8]
