# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate typed results, requested identities or verified failure alternatives.
# @@Verification={"group": "privacy", "expected": "proofReason"}
import ../../../src/state/proof/service as proof_service
import ../../../src/codec/state/accounts as state_accounts
let outcome = default(ServiceProofResult[ServiceMetadata])
discard outcome.proofReason
