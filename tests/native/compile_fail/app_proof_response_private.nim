# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Private state and authority cannot be inspected or forged by consumers.
import ../../../src/app/proof_query as app_proof_query
let private = default(ProofResponse)
discard private.data
