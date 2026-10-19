# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "SkippedAccumulation", "early": ["prepareCompleteAccumulationBatch(", "[4] expected: openArray but got: array[0..0, PreparedAccumulationService]"]}

## A resolved service alone cannot impersonate a certified non-executing outcome.

import ../../../src/state/[accumulation_batch, accumulation_inputs, accumulation_service,
    accumulation_dispatch, store]
import ../../../src/codec/header
var inputs: PreparedAccumulationInputs
var prior: StateStoreSnapshot
var service: PreparedAccumulationService
var limits: AccumulationBatchLimits
var executions: seq[AccumulationDispatchResult] = @[]
discard prepareCompleteAccumulationBatch(inputs, prior, executions, [service], HeaderSlot(0), limits)
