# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Sliced byte results retain private payload storage behind the generic store success contract.

import ../../../src/state/store as state_store
var outcome: StateStoreResult[seq[byte]]
discard outcome.completed
