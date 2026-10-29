# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A full-state reader cannot expose or replace its private native epoch owner.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/full/paged/store as full_paged_store
let reader = default(FullPagedReader)
discard reader.data
