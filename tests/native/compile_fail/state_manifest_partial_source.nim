# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "ValidatedGlobalState", "early": ["validateStateManifest(", "[1] expected: ValidatedGlobalState but got: ProofView"]}

## Reject mutable or partial-state shortcuts at the complete-manifest boundary.
import ../../../src/state/manifest
import ../../../src/state/proof_view
discard validateStateManifest(default(ProofView), [], default(StateManifestLimits))
