# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StoppedAccumulation", "early": ["prepareStoppedAccumulation(", "[1] expected: StoppedAccumulation but got: PreparedFinalAccumulation"]}

## Only the guarded genuine stopped driver alternative can authorize this composition path.

import ../../../src/state/[accumulation_completion, accumulation_finalization]
var source: PreparedFinalAccumulation
discard prepareStoppedAccumulation(source, default(AccumulationCompletionLimits))
