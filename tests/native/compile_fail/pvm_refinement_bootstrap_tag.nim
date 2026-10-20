# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private bootstrap or historical-preimage alternative storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/refinement_bootstrap
var owner: RefinementBootstrapResult[PreparedRefinementBootstrap]
discard owner.status
