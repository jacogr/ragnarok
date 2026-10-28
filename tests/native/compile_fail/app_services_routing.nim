# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypassing the service-owned canonical state or startup publication choice.
# @@Verification={"group": "privacy", "expected": "chainRpc"}

import ../../../src/app/services as app_services
var owner = default(Services)
discard owner.chainRpc
