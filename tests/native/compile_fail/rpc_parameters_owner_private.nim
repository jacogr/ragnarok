# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Checks that external mutation of Parameters storage is rejected at compile time.
# @@Verification={"group": "privacy", "expected": "numbers"}

import ../../../src/chain/parameters as chain_parameters
var snapshot = default(Parameters)
snapshot.numbers[coreCount] = 3
