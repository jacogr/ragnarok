# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared complete-state transport cannot expose mutable records or caller root authority.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/state/paged/state as paged_state
let prepared = default(PreparedPagedState)
discard prepared.data
