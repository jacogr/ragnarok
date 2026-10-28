# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached export trees or substituted validator and resource-policy domains.

# @@Verification={"group": "nominal", "expected": "ExportErasure", "early": ["prepareAvailabilityCommitment(", "[1] expected: ExportErasure but got: ExportCommitment"]}

import ../../../src/state/availability_specifier as state_availability_specifier
import ../../../src/state/export_erasure as state_export_erasure
import ../../../src/state/export_commitment as state_export_commitment
import ../../../src/state/erasure_layout as state_erasure_layout
discard prepareAvailabilityCommitment(default(ExportCommitment), AvailabilityCommitmentLimits())
