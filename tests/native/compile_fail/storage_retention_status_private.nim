# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retention ownership and result alternatives cannot be mutated through public handles.
# @@Verification={"group":"privacy","expected":"status"}
import ../../../src/storage/revision_retention as storage_revision_retention
let hidden = default(RetentionResult[RetentionToken])
discard hidden.status
