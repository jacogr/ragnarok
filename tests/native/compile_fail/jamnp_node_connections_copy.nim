# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A copied pool would retain dialer parent pointers and split multi-engine callback retirement.
# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <NodeConnections>","build_name":"jamnp-node-connections-copy","rationale":"The listener borrows the original pool address and each stable outgoing owner points back to it; duplicating the aggregate would leave callbacks bound to a different pool and create competing teardown authority.","reference":"spec/jamnp-node-connections.md"}
import ../../../src/jamnp-s/connections
var original = default(NodeConnections)
var duplicate = original
original.close() # Preserve the source use so lowering must duplicate rather than sink.
duplicate.close()
