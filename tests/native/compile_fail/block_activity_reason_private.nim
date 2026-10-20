# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refuse raw construction or retagging of original-block-bound block activity.

import ../../../src/state/block_activity
var outcome: BlockActivityResult[PreparedBlockActivity]
outcome.status = BlockActivityError.None
