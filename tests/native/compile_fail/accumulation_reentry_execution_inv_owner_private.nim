# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject private reentry bootstrap/completion payload access.

import ../../../src/state/accumulation_reentry_invocation
var owner: ReentryAccumulationInvocation
discard owner.data
