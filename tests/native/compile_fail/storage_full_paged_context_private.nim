# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque authenticated context cannot expose mutable bytes or forge native source authority.
# @@Verification={"group":"privacy","expected":"payload"}
import ../../../src/storage/full/paged/stream as full_paged_stream
let context = default(FullPagedContext)
discard context.payload
