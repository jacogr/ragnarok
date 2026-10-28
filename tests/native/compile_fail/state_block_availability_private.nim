# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot forge or read private availability transition storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "availabilityReason"}

import ../../../src/state/block_transition as state_block_transition
var outcome = default(BlockTransitionResult)
discard outcome.availabilityReason # Must fail before native generation.
