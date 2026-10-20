# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Host failure reasons cannot replace the engine's StepError domain.

# @@Verification={"group": "nominal", "expected": "got: StepError but wanted: RefinementDispatchError"}

import ../../../src/state/refinement_dispatch
import ../../../src/pvm/step
let outcome = default(RefinementDispatchResult[RefinementOutcome])
let wrong: RefinementDispatchError = outcome.executionError
discard wrong
