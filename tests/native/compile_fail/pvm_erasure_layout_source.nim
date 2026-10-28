# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted nominal policy/index types.

# @@Verification={"group": "nominal", "expected": "AuditableBundle", "early": ["prepareErasureLayout(", "[1] expected: AuditableBundle but got: InputRefinement"]}

import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/auditable_bundle as state_auditable_bundle
import ../../../src/state/input_refinement as state_input_refinement
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
discard prepareErasureLayout(default(InputRefinement), ErasureShards(6), ByteLimit(100))
