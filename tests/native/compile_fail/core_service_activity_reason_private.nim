# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Per-block activity ownership and result alternatives remain private.

import ../../../src/state/core/service_activity as core_service_activity
var outcome: CoreServiceActivityResult[int]
outcome.status = CoreServiceActivityError.None
