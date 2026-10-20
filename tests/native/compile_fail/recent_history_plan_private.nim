# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging of original-block-bound recent history.

import ../../../src/state/recent_history
var owner: PreparedRecentHistory
discard owner.data
