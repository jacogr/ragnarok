# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Bound preimage source, results and discriminators remain private.

import ../../../src/state/accumulation/preimages as accumulation_preimages
var owner: PreparedAccumulationPreimages
discard owner.data
