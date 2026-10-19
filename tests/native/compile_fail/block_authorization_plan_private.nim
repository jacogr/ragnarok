# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging of source-bound authorization owners/results.

import ../../../src/state/block_authorization
var owner: PreparedBlockAuthorization
discard owner.data
