# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Paged codec metadata remains private behind validated constructors and guarded accessors.
# @@Verification={"group": "privacy", "expected": "tree"}
import ../../../src/storage/paged_codec as storage_paged_codec
let hidden = default(PagedManifest)
discard hidden.tree
