# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Paged codec metadata remains private behind validated constructors and guarded accessors.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/storage/paged_codec
let hidden = default(PagedCodecResult[PagedHeader])
discard hidden.completed
