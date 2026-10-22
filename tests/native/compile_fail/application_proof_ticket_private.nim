# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "owner"}

## Private state and authority cannot be inspected or forged by consumers.
import ../../../src/app/proof_worker
let private = default(ProofWorkerTicket)
discard private.owner
