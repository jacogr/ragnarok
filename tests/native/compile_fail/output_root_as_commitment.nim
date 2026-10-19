# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trie roots cannot silently become service output commitments.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: StateNodeHash but wanted: OutputCommitment"}

import ../../../src/codec/[state_outputs, state_layout]
let value = AccumulationOutput(commitment: default(StateNodeHash))
discard value
