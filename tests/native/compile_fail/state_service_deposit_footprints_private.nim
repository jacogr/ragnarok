# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "footprints"}

## Caller cannot forge source-bound deposit authority or mutate failure alternatives.
import ../../../src/state/service/deposit as service_deposit
var value = default(ServiceDepositObservation)
discard value.footprints
