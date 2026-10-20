# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted indices and scalar-only allocation policy.

# @@Verification={"group": "nominal", "expected": "BundleErasureLimits", "early": ["prepareBundleErasure(", "[2] expected: BundleErasureLimits but got: ErasureWordLimits"]}

import ../../../src/state/[bundle_erasure, erasure_layout, erasure_words, auditable_bundle]
discard prepareBundleErasure(default(ErasureLayout), ErasureWordLimits())
