# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A regular leaf value digest is not a child-node identity.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StateValueHash"}

import ../../../src/codec/state_layout
let wrong = default(StateValueHash)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
