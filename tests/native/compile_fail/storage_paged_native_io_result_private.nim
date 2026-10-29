# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private io_result state cannot forge a native resource or successful receipt.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/storage/paged/io as paged_io
let outcome = default(PagedIoResult[bool])
discard outcome.completed
