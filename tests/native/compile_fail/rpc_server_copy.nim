# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A composite RPC owner cannot duplicate its listener and accepted sockets.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <Server>", "build_name": "rpc-server-copy"}

import ../../../src/rpc/server
var original = default(Server)
var duplicate = original
original.close()
duplicate.close()
