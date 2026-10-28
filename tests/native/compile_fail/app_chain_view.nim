# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"view"}

## Callers cannot independently replace a canonical state or history field.

import ../../../src/app/chain as app_chain
let owner = default(ApplicationChain)
discard owner.view
