# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal","expected": "SkippedAccumulation","early": ["prepareCompleteAccumulationBatch(","[4] expected: openArray[SkippedAccumulation] but got: array[0..0, PreparedAccumulationService]"]}

## A resolved service alone cannot impersonate a certified non-executing outcome.

import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/store as state_store
import ../../../src/codec/header as codec_header
var inputs: PreparedAccumulationInputs
var prior: StateStoreSnapshot
var service: PreparedAccumulationService
var limits: AccumulationBatchLimits
var executions: seq[AccumulationDispatchResult] = @[]
discard prepareCompleteAccumulationBatch(inputs, prior, executions, [service], HeaderSlot(0), limits)
