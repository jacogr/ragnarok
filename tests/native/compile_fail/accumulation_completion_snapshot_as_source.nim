# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StoppedAccumulation", "early": ["prepareStoppedAccumulation(", "[1] expected: StoppedAccumulation but got: StateStoreSnapshot"]}

## Only the guarded genuine stopped driver alternative can authorize this composition path.

import ../../../src/state/accumulation/completion as accumulation_completion
import ../../../src/state/store
var source: StateStoreSnapshot
discard prepareStoppedAccumulation(source, default(AccumulationCompletionLimits))
