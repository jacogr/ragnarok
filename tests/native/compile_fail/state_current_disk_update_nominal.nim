# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedChainUpdate but got: PreparedCurrentDiskPublication", "early": ["owner.(installPrepared,", "[2] expected: PreparedChainUpdate but got: PreparedCurrentDiskPublication"]}

## Disk authority cannot substitute for a current prepared chain update.
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_chain as app_disk_chain
var owner = default(ApplicationChain)
owner.installPrepared(default(PreparedCurrentDiskPublication))
