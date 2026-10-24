# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Streamed admission metadata and selected results remain private behind guarded accessors.
# @@Verification={"group":"privacy","expected":"policy"}
import ../../../src/storage/paged_stream
let hidden = default(CheckedPagedArtifact)
discard hidden.policy
