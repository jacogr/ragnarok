# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationStatistics", "early": ["prepareServiceActivity(", "[1] expected: PreparedAccumulationStatistics but got: PreparedFinalAccumulation"]}

## A raw projection or finalized state cannot replace genuine statistics and original block provenance.

import ../../../src/state/[service_activity, accumulation_finalization]
var source: PreparedFinalAccumulation
var config: ServiceActivityConfig
discard prepareServiceActivity(source, config)
