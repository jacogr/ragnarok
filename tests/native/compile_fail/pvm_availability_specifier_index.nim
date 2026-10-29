# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached export trees or substituted validator and resource-policy domains.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["availabilityShard(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import ../../../src/state/availability/specifier as availability_specifier
import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/erasure/layout as erasure_layout
discard availabilityShard(default(AvailabilityCommitment), OriginalShardIndex(0))
