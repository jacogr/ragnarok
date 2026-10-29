# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Batch authority and tagged results keep their backing inaccessible to importers.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/storage/light/journal/cache as light_journal_cache
discard default(PreparedLightJournalBatch).data
