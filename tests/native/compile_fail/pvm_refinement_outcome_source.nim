# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public raw outcomes cannot replace the bootstrap-owned execution source.

# @@Verification={"group": "nominal", "expected": "PreparedRefinementBootstrap", "early": ["runRefinementInvocation(", "[1] expected: PreparedRefinementBootstrap but got: RefinementOutcome"]}

import ../../../src/state/refinement_outcome as state_refinement_outcome
import ../../../src/state/refinement_dispatch as state_refinement_dispatch
import ../../../src/pvm/refinement_exports as pvm_refinement_exports
discard runRefinementInvocation(default(RefinementOutcome), [], default(RefinementInputs),
  ExportOffset(0), default(RefinementInvocationLimits))
