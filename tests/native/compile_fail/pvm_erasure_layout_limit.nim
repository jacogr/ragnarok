# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted nominal policy/index types.

# @@Verification={"group": "nominal", "expected": "ByteLimit", "early": ["prepareErasureLayout(", "[3] expected: ByteLimit but got: BundleLength"]}

import ../../../src/state/[erasure_layout, auditable_bundle, input_refinement]
import ../../../src/codec/[bounded, work_report]
discard prepareErasureLayout(default(AuditableBundle), ErasureShards(6), BundleLength(100))
