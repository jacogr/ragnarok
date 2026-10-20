# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypassing the single-slot candidate/result owner and its selected state.
# @@Verification={"group": "privacy", "expected": "adoption"}

import ../../../src/app/services
var owner = default(Services)
discard owner.adoption
