# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Caller cannot forge source-bound deposit authority or mutate failure alternatives.
import ../../../src/state/service_deposit
var value = default(ServiceDepositResult[ServiceDepositObservation])
discard value.status
