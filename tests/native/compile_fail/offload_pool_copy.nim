# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot forge pending results or duplicate a live worker-pool owner.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <OffloadPool>","build_name":"offload-pool-copy","offload":true,"rationale":"The offload-enabled native proof pool lends its stable stack address to joined workers; duplication would split cancellation, lock and worker-join authority.","reference":"src/jamnp-s/offload.nim"}

import "../../../src/jamnp-s/offload"
var original = default(OffloadPool)
var duplicate = original
discard busyPool(original)
discard busyPool(duplicate)
