# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Streamed admission metadata and selected results remain private behind guarded accessors.
# @@Verification={"group":"privacy","expected":"proofCause"}
import ../../../src/storage/paged/stream as paged_stream
let hidden = default(PagedStreamResult[CheckedPagedArtifact])
discard hidden.proofCause
