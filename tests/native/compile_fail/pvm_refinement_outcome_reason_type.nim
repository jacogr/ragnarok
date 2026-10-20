# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Engine step reasons cannot silently become callback/dispatch reasons.

# @@Verification={"group": "nominal", "expected": "got: StepError but wanted: RefinementDispatchError"}

import ../../../src/state/[refinement_outcome, refinement_dispatch]
let outcome = default(RefinementInvocationResult[RefinementInvocation])
let wrong: RefinementDispatchError = outcome.executionError
discard wrong
