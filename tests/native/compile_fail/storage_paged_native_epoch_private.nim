# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private epoch state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"identity"}
import ../../../src/storage/paged/store as paged_store
let outcome = default(PagedEpochReceipt)
discard outcome.identity
