# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private file state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/paged_io
let outcome = default(PagedFile)
discard outcome.data
