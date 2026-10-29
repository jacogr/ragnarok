# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private refinement execution ownership and alternative storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/refinement/dispatch as refinement_dispatch
var owner: PreparedRefinementExecution
discard owner.data
