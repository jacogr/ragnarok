# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: the provider snapshot is private to its immutable owner.
# @@Verification={"group": "privacy", "expected": "snapshot"}

import ../../../src/chain/provider
var view = default(ChainView)
discard view.snapshot
