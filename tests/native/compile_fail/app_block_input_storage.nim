# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot replace the receiver's private mutable byte/context storage.
# @@Verification={"group": "privacy", "expected": "pending"}

import ../../../src/app/block_input as app_block_input
var owner = default(BlockInput)
discard owner.pending
