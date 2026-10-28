# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "previousReason"}

## Current profile/parameter/source storage and result alternatives remain private.
import ../../../src/state/current_profile as state_current_profile
var value = default(CurrentProfileResult[DerivedCurrentProfile])
discard value.previousReason
