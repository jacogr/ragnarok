# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted indices and scalar-only allocation policy.

# @@Verification={"group": "nominal", "expected": "ErasureLayout", "early": ["prepareBundleErasure(", "[1] expected: ErasureLayout but got: AuditableBundle"]}

import ../../../src/state/[bundle_erasure, erasure_layout, erasure_words, auditable_bundle]
discard prepareBundleErasure(default(AuditableBundle), BundleErasureLimits())
