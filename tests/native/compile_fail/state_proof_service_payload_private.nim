# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate typed results, requested identities or verified failure alternatives.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/proof_service as state_proof_service
import ../../../src/codec/state_accounts as codec_state_accounts
let outcome = default(ServiceProofResult[ServiceMetadata])
discard outcome.completed
