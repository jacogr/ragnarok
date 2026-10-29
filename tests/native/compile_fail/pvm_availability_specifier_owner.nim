# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private availability-root/result storage access.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/availability/specifier as availability_specifier
var candidate: AvailabilityCommitment
discard candidate.data
