# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private identity state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"file"}
import ../../../src/storage/paged_io as storage_paged_io
let outcome = default(PagedFileIdentity)
discard outcome.file
