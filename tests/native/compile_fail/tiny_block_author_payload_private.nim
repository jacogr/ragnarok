# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default authoring outcomes cannot grant access to a fabricated block payload.
# @@Verification={"group": "privacy", "expected": "completed"}
import "../../../src/app/block/author" as block_author
let outcome = default(BlockAuthorResult)
discard outcome.completed
