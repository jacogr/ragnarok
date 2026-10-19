# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: the retained discovery sequence cannot be mutated externally.
# @@Verification={"group": "privacy", "expected": "services"}

import ../../../src/chain/genesis
var owner = default(Genesis)
owner.services = @[]
