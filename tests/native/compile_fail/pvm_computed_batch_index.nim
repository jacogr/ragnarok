# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject per-guarantee ordinals at the batch boundary.

# @@Verification={"group": "nominal", "expected": "ComputedBatchIndex", "early": ["computedBatchSourceAt(", "[2] expected: ComputedBatchIndex but got: ComputedReporterIndex"]}

import ../../../src/state/computed/[batch as computed_batch, envelope as computed_envelope]
discard computedBatchSourceAt(default(ComputedGuaranteeBatch), ComputedReporterIndex(0))
