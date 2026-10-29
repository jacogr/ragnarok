# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedAccumulationContinuation", "early": ["prepareAccumulationReentry(", "[1] expected: CompletedAccumulationContinuation but got: CompletedBlockAccumulation"]}

## Reject substitution of nominal reentry source/report domains.

import ../../../src/state/accumulation/[reentry as accumulation_reentry,
    execution as accumulation_execution]
var initial: CompletedBlockAccumulation
discard prepareAccumulationReentry(initial, default(AccumulationReentryConfig))
