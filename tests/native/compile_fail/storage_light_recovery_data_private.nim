# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recovery resources remain private behind explicit inspection, repair and close.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/storage/light/journal/cache as light_journal_cache
let hidden = default(LightJournalRecovery)
discard hidden.data
