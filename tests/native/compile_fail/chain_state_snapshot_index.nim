# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"StateEntryIndex","early":["source.(keyAt,","[2] expected: StateEntryIndex but got: StateKeyIndex"]}

## Chain pagination coordinates cannot silently substitute for store enumeration coordinates.

import ../../../src/state/store as state_store
import ../../../src/chain/genesis as chain_genesis
let source = default(StateStoreSnapshot)
discard source.keyAt(StateKeyIndex(0))
