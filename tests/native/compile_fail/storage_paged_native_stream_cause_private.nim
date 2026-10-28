# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The selected native result discriminator/cause is private and cannot be forged.
# @@Verification={"group":"privacy","expected":"streamCause"}
import ../../../src/storage/paged_store as storage_paged_store
let outcome = default(PagedNativeResult[bool])
discard outcome.streamCause
