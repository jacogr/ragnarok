# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Root-advance authority stays behind opaque and success-guarded public accessors.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
let hidden = default(PreparedLightRootAdvance)
discard hidden.data
