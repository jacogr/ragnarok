# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StoppedAccumulation", "early": ["prepareStoppedAccumulation(", "[1] expected: StoppedAccumulation but got: CompletedAccumulationReentry"]}

## Only the guarded genuine stopped driver alternative can authorize this composition path.

import ../../../src/state/accumulation/[completion as accumulation_completion,
    reentry as accumulation_reentry]
var source: CompletedAccumulationReentry
discard prepareStoppedAccumulation(source, default(AccumulationCompletionLimits))
