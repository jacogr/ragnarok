# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Database identity and result backing stay private.
# @@Verification={"group":"privacy","expected":"initialized"}
import ../../../src/storage/database_identity
let hidden = default(DatabaseIdentity)
discard hidden.initialized
