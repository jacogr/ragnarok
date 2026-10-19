# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedServiceActivity", "early": ["prepareBlockActivity(", "[1] expected: PreparedServiceActivity but got: ActivityState"]}

## A raw projection cannot replace genuine report admission and original block provenance.

import ../../../src/state/[block_activity]
import ../../../src/codec/state_statistics
var source: ActivityState
var config: BlockActivityConfig
discard prepareBlockActivity(source, config)
