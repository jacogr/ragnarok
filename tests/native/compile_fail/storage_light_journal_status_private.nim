# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The journal owner and selected result payloads remain private behind lifecycle and success guards.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/storage/light_journal_cache
let hidden = default(LightJournalResult[int])
discard hidden.status
