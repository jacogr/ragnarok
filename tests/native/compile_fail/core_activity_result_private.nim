# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse raw construction or retagging of original-block-bound core activity.

import ../../../src/state/core_activity
var outcome: CoreActivityResult[PreparedCoreActivity]
discard outcome.completed
