# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuation", "early": ["prepareAccumulationContinuationInputs(", "[1] expected: PreparedAccumulationContinuation but got: PreparedAccumulationInputs"]}

## Refuse access or domain substitution across continuation input/state preparation.

import ../../../src/state/[accumulation_continuation_inputs, accumulation_inputs]
var inputs: PreparedAccumulationInputs
var config: AccumulationContinuationInputConfig
discard prepareAccumulationContinuationInputs(inputs, config)
