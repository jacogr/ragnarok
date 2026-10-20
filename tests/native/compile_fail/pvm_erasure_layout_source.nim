# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted nominal policy/index types.

# @@Verification={"group": "nominal", "expected": "AuditableBundle", "early": ["prepareErasureLayout(", "[1] expected: AuditableBundle but got: InputRefinement"]}

import ../../../src/state/[erasure_layout, auditable_bundle, input_refinement]
import ../../../src/codec/[bounded, work_report]
discard prepareErasureLayout(default(InputRefinement), ErasureShards(6), ByteLimit(100))
