# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Root-advance authority stays behind opaque and success-guarded public accessors.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/storage/light_journal_cache
let hidden = default(LightJournalResult[PreparedLightRootAdvance])
discard hidden.status
