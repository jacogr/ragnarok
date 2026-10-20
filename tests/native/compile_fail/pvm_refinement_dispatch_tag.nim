# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private refinement execution ownership and alternative storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/refinement_dispatch
var owner: RefinementDispatchResult[RefinementOutcome]
discard owner.status
