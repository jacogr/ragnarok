# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationReportStart", "early": ["prepareAccumulationOperandRange(", "[2] expected: AccumulationReportStart but got: AccumulationReportPrefix"]}

## Refuse access or domain substitution across continuation input/state preparation.

import ../../../src/state/[accumulation_operands, accumulation_queue]
var queue: AccumulationQueuePlan
var config: AccumulationOperandConfig
discard prepareAccumulationOperandRange(queue, AccumulationReportPrefix(0),
    AccumulationReportPrefix(0), config)
