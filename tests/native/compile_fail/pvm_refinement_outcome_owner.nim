# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private normalized ownership, payloads and alternative-specific refusal storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/refinement/outcome as refinement_outcome
var owner: RefinementInvocation
discard owner.data
