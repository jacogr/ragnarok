# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject per-guarantee ordinals at the batch boundary.

# @@Verification={"group": "nominal", "expected": "ComputedBatchReporterIndex", "early": ["computedBatchReporterAt(", "[2] expected: ComputedBatchReporterIndex but got: ComputedReporterIndex"]}

import ../../../src/state/[computed_batch, computed_envelope]
discard computedBatchReporterAt(default(ComputedGuaranteeBatch), ComputedReporterIndex(0))
