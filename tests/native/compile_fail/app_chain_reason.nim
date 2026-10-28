# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"chainReason"}

## Application constructor results hide mutable tags, successful owners and unselected child reasons.

import ../../../src/app/chain as app_chain
let outcome = default(ApplicationChainResult[ApplicationChain])
discard outcome.chainReason
