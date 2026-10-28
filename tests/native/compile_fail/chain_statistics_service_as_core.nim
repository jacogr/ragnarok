# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service dictionary ordinals cannot select core positions.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StatisticsServiceIndex"}

import ../../../src/codec/state_statistics as codec_state_statistics
let owner = default(ActivitySnapshot)
discard coreActivityAt(owner, StatisticsServiceIndex(0))
