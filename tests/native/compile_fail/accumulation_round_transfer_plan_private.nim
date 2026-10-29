# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Guarded completed-round ownership cannot be bypassed by direct field access.

import ../../../src/state/accumulation/round/transfers as accumulation_round_transfers
var plan: PreparedRoundAccumulationTransfers
discard plan.data
