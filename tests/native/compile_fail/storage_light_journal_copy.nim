# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Light file cache duplication must fail actual native lowering.
# @@Verification={"group":"ownership_compile","build_name":"storage-light-journal-copy","expected":"'=dup' is not available for type <LightJournalCache>"}
import ../../../src/storage/light_journal_cache
proc duplicated(source: LightJournalCache): LightJournalCache =
  ## A borrowed append owner cannot acquire another retirement authority.
  source
var first = default(LightJournalCache)
var second = duplicated(first)
discard first.opened
discard second.close
