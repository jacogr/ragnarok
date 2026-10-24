# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Paged codec metadata remains private behind validated constructors and guarded accessors.
# @@Verification={"group": "privacy", "expected": "start"}
import ../../../src/storage/paged_codec
let hidden = default(PagedDescriptor)
discard hidden.start
