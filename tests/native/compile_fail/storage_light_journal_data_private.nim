# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The journal owner and selected result payloads remain private behind lifecycle and success guards.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/storage/light/journal/cache as light_journal_cache
let hidden = default(LightJournalCache)
discard hidden.data
