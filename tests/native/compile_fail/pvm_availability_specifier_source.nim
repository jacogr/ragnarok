# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached export trees or substituted validator and resource-policy domains.

# @@Verification={"group": "nominal", "expected": "ExportErasure", "early": ["prepareAvailabilityCommitment(", "[1] expected: ExportErasure but got: ExportCommitment"]}

import ../../../src/state/[availability_specifier, export_erasure, export_commitment, erasure_layout]
discard prepareAvailabilityCommitment(default(ExportCommitment), AvailabilityCommitmentLimits())
