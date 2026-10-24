# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default admission results cannot expose unchecked complete-graph metadata.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/storage/full_paged_stream
let outcome = default(FullPagedStreamResult[CheckedFullPagedArtifact])
discard outcome.completed
