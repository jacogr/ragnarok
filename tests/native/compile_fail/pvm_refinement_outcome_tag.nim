# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private normalized ownership, payloads and alternative-specific refusal storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/refinement/outcome as refinement_outcome
var owner: RefinementInvocationResult[RefinementInvocation]
discard owner.status
