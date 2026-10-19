# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedBlockPreimages", "early": ["publishBlockPreimages(", "[1] expected: PreparedBlockPreimages but got: PublishedRecentHistory"]}

## Loose admission or completed recent history cannot replace this stage's exact owner.

import ../../../src/state/[block_preimages, recent_history]
var source: PublishedRecentHistory
discard publishBlockPreimages(source)
