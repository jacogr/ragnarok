# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot manufacture complete-graph authority by observing or changing a readiness flag.
# @@Verification={"group":"privacy","expected":"ready"}
import ../../../src/storage/full/paged/stream as full_paged_stream
let checked = default(CheckedFullPagedArtifact)
discard checked.ready
