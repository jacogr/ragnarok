# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedBlockActivity", "early": ["publishBlockActivity(", "[1] expected: PreparedBlockActivity but got: PreparedServiceActivity"]}

## Raw service metrics cannot replace complete source-matched C(13) preparation at publication.

import "../../../src/state/block/activity" as block_activity
import ../../../src/state/service/activity as service_activity
var source: PreparedServiceActivity
discard publishBlockActivity(source)
