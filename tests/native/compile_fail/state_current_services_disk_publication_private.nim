# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Producers cannot replace the saved current publication that binds the actual IO receipt.
# @@Verification={"group": "privacy", "expected": "currentDiskPublication"}

import ../../../src/app/services as app_services
var owner = default(Services)
discard owner.currentDiskPublication
