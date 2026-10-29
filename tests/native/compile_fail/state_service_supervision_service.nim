# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "ServiceIndex", "early": ["resolveServiceSupervision(", "[2] expected: ServiceIndex but got: AccountSlot"]}

## A creation slot cannot select a service identity.
import ../../../src/state/service/[supervision as service_supervision,
    directory as service_directory]
import ../../../src/codec/state/accounts as state_accounts
discard resolveServiceSupervision(default(StateServiceDirectory), AccountSlot(7))
