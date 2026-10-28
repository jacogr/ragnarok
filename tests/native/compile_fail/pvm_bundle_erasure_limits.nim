# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted indices and scalar-only allocation policy.

# @@Verification={"group": "nominal", "expected": "BundleErasureLimits", "early": ["prepareBundleErasure(", "[2] expected: BundleErasureLimits but got: ErasureWordLimits"]}

import ../../../src/state/bundle_erasure as state_bundle_erasure
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/erasure_words as state_erasure_words
import ../../../src/state/auditable_bundle as state_auditable_bundle
discard prepareBundleErasure(default(ErasureLayout), ErasureWordLimits())
