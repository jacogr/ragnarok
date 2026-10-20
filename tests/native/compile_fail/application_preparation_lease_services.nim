# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "worker"}

## Private preparation ownership and RPC release authority cannot escape through fields.
import ../../../src/app/services
import ../../../src/rpc/server
let private = default(Services)
discard private.worker
