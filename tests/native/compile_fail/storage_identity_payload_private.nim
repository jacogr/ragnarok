# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Database identity and result backing stay private.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/storage/database_identity
let hidden = default(IdentityResult[DatabaseIdentity])
discard hidden.completed
