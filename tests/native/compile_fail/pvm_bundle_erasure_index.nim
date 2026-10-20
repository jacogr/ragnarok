# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted indices and scalar-only allocation policy.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["bundleErasureChunk(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import ../../../src/state/[bundle_erasure, erasure_layout, erasure_words, auditable_bundle]
discard bundleErasureChunk(default(BundleErasure), OriginalShardIndex(0))
