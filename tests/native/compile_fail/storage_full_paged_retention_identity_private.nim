# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Passive cleanup authority cannot expose or substitute its captured native inode/namespace identity.
# @@Verification={"group":"privacy","expected":"identity"}
import ../../../src/storage/full/paged/store as full_paged_store
let receipt = default(FullPagedEpochReceipt)
discard receipt.identity
