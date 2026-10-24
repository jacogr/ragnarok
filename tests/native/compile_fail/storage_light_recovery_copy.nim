# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Light file cache duplication must fail actual native lowering.
# @@Verification={"group":"ownership_compile","build_name":"storage-light-recovery-copy","expected":"'=dup' is not available for type <LightJournalRecovery>"}
import ../../../src/storage/light_journal_cache
proc duplicated(source: LightJournalRecovery): LightJournalRecovery =
  ## A borrowed append owner cannot acquire another retirement authority.
  source
var first = default(LightJournalRecovery)
var second = duplicated(first)
discard first.opened
discard second.close
