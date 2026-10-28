# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationValidators", "early": ["prepareAccumulationActivity(", "[1] expected: PreparedAccumulationValidators but got: ActivitySnapshot"]}

## Detached statistics cannot construct a certified combined activity candidate.

import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/codec/state_statistics as codec_state_statistics
var source: ActivitySnapshot
var config: AccumulationActivityConfig
discard prepareAccumulationActivity(source, config)
