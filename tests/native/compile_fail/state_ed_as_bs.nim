# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Different public-key schemes retain nominal roles even at the same encoded width.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: StateEdKey but wanted: StateBsKey"}

import ../../../src/codec/state_safrole as codec_state_safrole
let key = default(StateEdKey)
let validator = StateValidator(bandersnatch: key)
discard validator
