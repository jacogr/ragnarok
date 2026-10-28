# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationStatistics", "early": ["prepareAccumulationAccounts(", "[1] expected: PreparedAccumulationStatistics but got: AccumulationAccountProjection"]}

## A raw projection or finalization cannot replace genuine accumulated statistics.

import ../../../src/state/accumulation_accounts as state_accumulation_accounts
var source: AccumulationAccountProjection
var config: AccumulationAccountConfig
discard prepareAccumulationAccounts(source, config)
