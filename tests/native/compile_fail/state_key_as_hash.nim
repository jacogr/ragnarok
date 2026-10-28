# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A 31-octet state key cannot stand in for a complete 32-octet child hash.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StateKey"}

import ../../../src/codec/state_layout as codec_state_layout
let wrong = default(StateKey)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
