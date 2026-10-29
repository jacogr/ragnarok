# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private availability-root/result storage access.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/availability/specifier as availability_specifier
var candidate: AvailabilityCommitmentResult[AvailabilityCommitment]
discard candidate.completed
