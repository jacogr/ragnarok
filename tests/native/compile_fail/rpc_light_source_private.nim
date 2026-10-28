# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private backing cannot grant forged partial runtime or transport authority.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/rpc/light_source as rpc_light_source
let source = default(RpcLightHead)
discard source.data
