# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging of original-block-bound core activity.

import ../../../src/state/core_activity
var owner: PreparedCoreActivity
discard owner.data
