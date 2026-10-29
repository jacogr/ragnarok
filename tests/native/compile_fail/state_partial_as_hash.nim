# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A truncated left commitment cannot implicitly become a complete child-node hash.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "LeftChildCommitment"}

import ../../../src/codec/state/layout as state_layout
let wrong = default(LeftChildCommitment)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
