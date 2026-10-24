# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private evidence/result backing cannot be forged or mutated by consumers.
# @@Verification={"group":"privacy","expected":"status"}
import ../../../src/state/paged_proof_view
let outcome = default(PagedProofViewResult[int])
discard outcome.status
