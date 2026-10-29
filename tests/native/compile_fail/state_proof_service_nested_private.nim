# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate typed results, requested identities or verified failure alternatives.
# @@Verification={"group": "privacy", "expected": "keys"}
import ../../../src/state/proof/service as proof_service
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
let plan = planProofAccount(ServiceIndex(7), ElementLimit(1)).value
discard plan.keys
