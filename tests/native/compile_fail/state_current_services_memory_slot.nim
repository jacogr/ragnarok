# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Producers cannot forge or replace Services' private current handoff state.
# @@Verification={"group": "privacy", "expected": "currentAdoption"}

import ../../../src/app/services as app_services
var owner = default(Services)
discard owner.currentAdoption
