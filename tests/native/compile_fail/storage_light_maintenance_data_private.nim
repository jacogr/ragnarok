# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact-source maintenance plans expose no mutable metadata or internal compaction candidate.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/light_journal_cache
let hidden = default(PreparedLightMaintenance)
discard hidden.data
