# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"chainReason"}

## RPC publication results hide mutable tags and payloads behind selected accessors.

import ../../../src/rpc/server as rpc_server
let outcome = default(RpcAccumulationResult)
discard outcome.chainReason
