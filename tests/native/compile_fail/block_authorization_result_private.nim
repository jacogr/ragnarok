# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse raw construction or retagging of source-bound authorization owners/results.

import ../../../src/state/block_authorization
var outcome: BlockAuthorizationResult[PreparedBlockAuthorization]
discard outcome.completed
