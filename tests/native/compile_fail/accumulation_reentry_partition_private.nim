# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "partitionReason"}

## A refused scheduling result cannot reveal or replace its private partition discriminator payload.

import ../../../src/state/accumulation/reentry as accumulation_reentry
import ../../../src/state/accumulation/continuation/execution as accumulation_continuation_execution
let refused = prepareAccumulationReentry(default(CompletedAccumulationContinuation), default(
    AccumulationReentryConfig))
discard refused.partitionReason
