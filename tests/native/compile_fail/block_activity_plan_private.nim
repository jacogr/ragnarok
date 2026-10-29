# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging of original-block-bound block activity.

import "../../../src/state/block/activity" as block_activity
var owner: PreparedBlockActivity
discard owner.data
