# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage, parameter tuple or copied facts as a completed configured context.

# @@Verification={"group": "nominal", "expected": "GenesisResult", "early": ["bindComputedProfile(", "[2] expected: GenesisResult but got: Parameters"]}

import ../../../src/state/computed/[profile as computed_profile, lookup as computed_lookup,
    recent as computed_recent]
import ../../../src/chain/[genesis, parameters]
discard bindComputedProfile(default(LookupAnchoredComputedReport), default(Parameters))
