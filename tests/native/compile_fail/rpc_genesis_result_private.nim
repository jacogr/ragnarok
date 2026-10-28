# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Reject external retagging of an unavailable genesis result.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/chain/genesis as chain_genesis
var decoded = unavailableGenesis()
decoded.status = GenesisError.None
