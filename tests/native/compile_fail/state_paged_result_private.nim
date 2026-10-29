# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite full-state transport results retain a private selected discriminator.
# @@Verification={"group":"privacy","expected":"status"}
import ../../../src/state/paged/state as paged_state
let outcome = default(PagedStateResult[int])
discard outcome.status
