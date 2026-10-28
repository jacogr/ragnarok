# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <StateProofWorker>", "build_name": "application-proof-worker-copy"}

## Reject duplicated composite thread owners during actual ownership lowering.
import ../../../src/app/proof_worker as app_proof_worker
var original = default(StateProofWorker)
var duplicate = original
original.close()
duplicate.close()
