# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Reject external access to the retained genesis keys owner.
# @@Verification={"group": "privacy", "expected": "keys"}

import ../../../src/chain/genesis as chain_genesis
var view = default(Genesis)
discard view.keys
