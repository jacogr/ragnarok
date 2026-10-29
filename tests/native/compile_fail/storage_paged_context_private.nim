# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private context storage cannot be forged or mutated through the public transport API.
# @@Verification={"group":"privacy","expected":"payload"}
import ../../../src/storage/paged/stream as paged_stream
var context = default(PagedContext)
context.payload = @[1'u8]
