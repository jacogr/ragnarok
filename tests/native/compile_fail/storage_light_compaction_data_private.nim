# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared compaction image and anchor backing remain private immutable authority.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/light_journal_cache
let hidden = default(PreparedLightCompaction)
discard hidden.data
