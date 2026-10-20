# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypassing the service-owned canonical state or startup publication choice.
# @@Verification={"group": "privacy", "expected": "canonical"}

import ../../../src/app/services
var owner = default(Services)
discard owner.canonical
