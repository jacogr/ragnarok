# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached export trees or substituted validator and resource-policy domains.

# @@Verification={"group": "nominal", "expected": "AvailabilityCommitmentLimits", "early": ["prepareAvailabilityCommitment(", "[2] expected: AvailabilityCommitmentLimits but got: ExportErasureLimits"]}

import ../../../src/state/availability/specifier as availability_specifier
import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/erasure/layout as erasure_layout
discard prepareAvailabilityCommitment(default(ExportErasure), ExportErasureLimits())
