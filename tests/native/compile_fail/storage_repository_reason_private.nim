# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repository backing and tagged payloads stay private.
# @@Verification={"group":"privacy","expected":"recordReason"}
import ../../../src/storage/node/repository as node_repository
let hidden = default(RepositoryResult[RepositoryView])
discard hidden.recordReason
