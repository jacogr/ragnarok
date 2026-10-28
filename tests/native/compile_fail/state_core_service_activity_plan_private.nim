# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Per-block activity ownership and result alternatives remain private.

import ../../../src/state/core_service_activity as state_core_service_activity
var owner: CoreServiceActivityProjection
discard owner.data
