# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate typed results, requested identities or verified failure alternatives.
# @@Verification={"group": "privacy", "expected": "keys"}
import ../../../src/state/proof_service as state_proof_service
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
let plan = planProofAccount(ServiceIndex(7), ElementLimit(1)).value
discard plan.keys
