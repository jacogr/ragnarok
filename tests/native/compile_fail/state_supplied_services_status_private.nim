# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Detached projection alternatives stay private and success-guarded.
import ../../../src/state/supplied_services
var outcome = default(SuppliedServicesResult)
discard outcome.status
