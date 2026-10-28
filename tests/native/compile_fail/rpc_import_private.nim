# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private backing cannot grant forged partial runtime or transport authority.
# @@Verification={"group":"privacy","expected":"wire"}
import ../../../src/rpc/proof_requests as rpc_proof_requests
let request = default(RpcProofRequest)
discard request.wire
