# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot forge pending results or duplicate a live worker-pool owner.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "hasCompletion"}

import ../../../src/quic/offload
discard OffloadPollResult(hasCompletion: true)
