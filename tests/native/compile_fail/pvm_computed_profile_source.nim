# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage, parameter tuple or copied facts as a completed configured context.

# @@Verification={"group": "nominal", "expected": "LookupAnchoredComputedReport", "early": ["bindComputedProfile(", "[1] expected: LookupAnchoredComputedReport but got: RecentComputedReport"]}

import ../../../src/state/[computed_profile, computed_lookup, computed_recent]
import ../../../src/chain/[genesis, parameters]
discard bindComputedProfile(default(RecentComputedReport), default(BlockSnapshotResult))
