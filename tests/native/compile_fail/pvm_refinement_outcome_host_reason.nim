# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private normalized ownership, payloads and alternative-specific refusal storage.

# @@Verification={"group": "privacy", "expected": "hostReason"}

import ../../../src/state/refinement_outcome as state_refinement_outcome
var owner: RefinementInvocationResult[RefinementInvocation]
discard owner.hostReason
