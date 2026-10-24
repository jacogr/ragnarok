# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private result state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/storage/paged_store
let outcome = default(PagedNativeResult[bool])
discard outcome.completed
