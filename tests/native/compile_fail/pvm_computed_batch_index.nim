# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject per-guarantee ordinals at the batch boundary.

# @@Verification={"group": "nominal", "expected": "ComputedBatchIndex", "early": ["computedBatchSourceAt(", "[2] expected: ComputedBatchIndex but got: ComputedReporterIndex"]}

import ../../../src/state/computed_batch as state_computed_batch
import ../../../src/state/computed_envelope as state_computed_envelope
discard computedBatchSourceAt(default(ComputedGuaranteeBatch), ComputedReporterIndex(0))
