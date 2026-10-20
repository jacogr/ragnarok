# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached export trees or substituted validator and resource-policy domains.

# @@Verification={"group": "nominal", "expected": "AvailabilityCommitmentLimits", "early": ["prepareAvailabilityCommitment(", "[2] expected: AvailabilityCommitmentLimits but got: ExportErasureLimits"]}

import ../../../src/state/[availability_specifier, export_erasure, export_commitment, erasure_layout]
discard prepareAvailabilityCommitment(default(ExportErasure), ExportErasureLimits())
