# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A 144-byte validator BLS key cannot silently replace the ring commitment of equal width.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: StateBlsKey but wanted: StateRingRoot"}

import ../../../src/codec/[state_consensus, state_safrole]
let key = default(StateBlsKey)
let source = SafroleState(root: key)
discard source
