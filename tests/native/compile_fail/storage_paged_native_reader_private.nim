# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private reader state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/paged_store as storage_paged_store
let outcome = default(PagedReader)
discard outcome.data
