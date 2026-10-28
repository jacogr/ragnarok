# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: clients cannot mutate the connection-local subscription table.
# @@Verification={"group": "privacy", "expected": "active"}

import ../../../src/rpc/protocol as rpc_protocol
var session = default(RpcSession)
discard session.active
