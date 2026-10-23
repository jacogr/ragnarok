# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pagination authority and private payloads are accessible only through checked APIs.
# @@Verification={"group":"privacy","expected":"offset"}
import ../../../src/storage/light_snapshot
let hidden = default(LightProofCursor)
discard hidden.offset
