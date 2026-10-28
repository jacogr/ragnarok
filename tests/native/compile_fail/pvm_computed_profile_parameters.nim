# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage, parameter tuple or copied facts as a completed configured context.

# @@Verification={"group": "nominal", "expected": "GenesisResult", "early": ["bindComputedProfile(", "[2] expected: GenesisResult but got: Parameters"]}

import ../../../src/state/computed_profile as state_computed_profile
import ../../../src/state/computed_lookup as state_computed_lookup
import ../../../src/state/computed_recent as state_computed_recent
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/parameters as chain_parameters
discard bindComputedProfile(default(LookupAnchoredComputedReport), default(Parameters))
