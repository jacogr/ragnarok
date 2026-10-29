# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private bootstrap or historical-preimage alternative storage.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/refinement/bootstrap as refinement_bootstrap
var owner: RefinementBootstrapResult[PreparedRefinementBootstrap]
discard owner.completed
