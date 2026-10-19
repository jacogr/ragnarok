# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Per-block activity ownership and result alternatives remain private.

import ../../../src/state/core_service_activity
var outcome: CoreServiceActivityResult[int]
discard outcome.completed
