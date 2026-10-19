# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse direct mutation or construction of source-bound preimage owners/results.

import ../../../src/state/block_preimages
var owner: PreparedBlockPreimages
discard owner.data
