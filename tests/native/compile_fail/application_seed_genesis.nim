# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"genesisReason"}

## Configured-seed failure payloads remain private behind selected read-only accessors.

import ../../../src/app/chain
let outcome = default(ApplicationChainResult[ApplicationChain])
discard outcome.genesisReason
