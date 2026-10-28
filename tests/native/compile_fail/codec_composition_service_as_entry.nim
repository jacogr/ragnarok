# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service identities cannot silently select mapping ordinals.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: StateEntryIndex but got: ServiceIndex"}

import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
discard stateEntryAt(default(StateSnapshot), ServiceIndex(0))
