# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Query and cancelled completions cannot expose unselected ingestion outcomes.
# @@Verification={"group":"privacy","expected":"ingestion"}
import ../../../src/app/proof_worker as app_proof_worker
let completion = default(ProofWorkerCompletion)
discard completion.ingestion
