# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedChainUpdate but got: PreparedCurrentDiskPublication", "early": ["owner.(installPrepared,", "[2] expected: PreparedChainUpdate but got: PreparedCurrentDiskPublication"]}

## Disk authority cannot substitute for a current prepared chain update.
import ../../../src/app/chain
import ../../../src/app/disk/chain as disk_chain
var owner = default(ApplicationChain)
owner.installPrepared(default(PreparedCurrentDiskPublication))
