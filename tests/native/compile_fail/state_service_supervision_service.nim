# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "ServiceIndex", "early": ["resolveServiceSupervision(", "[2] expected: ServiceIndex but got: AccountSlot"]}

## A creation slot cannot select a service identity.
import ../../../src/state/service_supervision as state_service_supervision
import ../../../src/state/service_directory as state_service_directory
import ../../../src/codec/state_accounts as codec_state_accounts
discard resolveServiceSupervision(default(StateServiceDirectory), AccountSlot(7))
