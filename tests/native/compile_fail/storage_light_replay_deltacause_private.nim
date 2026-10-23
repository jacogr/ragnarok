# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only guarded checked replay and plan accessors grant publication or repair authority.
# @@Verification={"group": "privacy", "expected": "deltaCause"}
import ../../../src/storage/light_journal_replay
let hidden = default(LightReplayResult[LightJournalReplay])
discard hidden.deltaCause
