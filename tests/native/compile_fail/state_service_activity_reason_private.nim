# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refuse raw construction or retagging of original-block-bound service activity.

import ../../../src/state/service_activity as state_service_activity
var outcome: ServiceActivityResult[PreparedServiceActivity]
outcome.status = ServiceActivityError.None
